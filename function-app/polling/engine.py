"""Config-driven polling engine.

Reads endpoint configuration from Azure App Configuration and orchestrates
API calls + data ingestion. Tracks failed endpoints for retry in the next run
(with TTL). Persists that list in Azure Table Storage so a Flex Consumption
cold start does not lose retry state.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
import uuid
from typing import Any

from azure.appconfiguration import AzureAppConfigurationClient
from azure.identity import DefaultAzureCredential
from azure.identity.aio import DefaultAzureCredential as AsyncDefaultAzureCredential

from .defender_client import DefenderClient
from .graph_client import GraphClient
from .ingestion import IngestionClient
from .state_store import FailedEndpointStore

logger = logging.getLogger(__name__)

DEFAULT_CONCURRENCY = 5

REQUIRED_ENDPOINT_KEYS = ("url", "scope", "stream", "dcr")


def _validate_endpoint(config: dict, source: str) -> bool:
    """Validate a single endpoint config; returns True when usable.

    Args:
        config: Parsed endpoint configuration.
        source: Human-readable origin (e.g. App Configuration key or
            ``endpoints.json:<schedule>``) used in warning messages.
    """
    missing = [key for key in REQUIRED_ENDPOINT_KEYS if not config.get(key)]
    if missing:
        logger.warning(
            "Skipping endpoint %s: missing required keys %s",
            source,
            ",".join(missing),
        )
        return False
    if config.get("transform") == "advancedHunting" and not config.get("query"):
        logger.warning(
            "Skipping endpoint %s: transform='advancedHunting' but no 'query' provided",
            source,
        )
        return False
    return True


def _ttl_seconds() -> int:
    """Return the failed-endpoint TTL, configurable via FAILED_ENDPOINT_TTL_HOURS."""
    raw = os.environ.get("FAILED_ENDPOINT_TTL_HOURS", "24")
    try:
        hours = int(raw)
    except ValueError:
        hours = 24
    return max(1, hours) * 3600


def _concurrency_limit() -> int:
    """Return the per-run endpoint concurrency (env POLL_CONCURRENCY)."""
    raw = os.environ.get("POLL_CONCURRENCY", str(DEFAULT_CONCURRENCY))
    try:
        return max(1, int(raw))
    except ValueError:
        return DEFAULT_CONCURRENCY


class PollingEngine:
    """Orchestrates fetching API data and ingesting it into Log Analytics."""

    def __init__(self) -> None:
        self._credential = DefaultAzureCredential()
        self._async_credential = AsyncDefaultAzureCredential()
        self._defender = DefenderClient(self._credential)
        self._graph = GraphClient(self._credential)
        self._ingestion = IngestionClient(self._async_credential)
        self._store = FailedEndpointStore(self._credential)
        self._appconfig: AzureAppConfigurationClient | None = None
        # In-memory fallback when Table Storage is not available.
        self._memory_failed: dict[str, list[tuple[float, dict]]] = {
            "daily": [],
            "weekly": [],
        }

    def _load_endpoints(self, prefix: str) -> list[dict]:
        """Load endpoint configuration from App Configuration.

        Args:
            prefix: Key prefix filter (e.g. ``endpoints:daily``).

        Returns:
            List of endpoint configuration dictionaries.
        """
        endpoint = os.environ.get("APP_CONFIG_ENDPOINT", "")
        if not endpoint:
            logger.warning("APP_CONFIG_ENDPOINT not configured, using fallback")
            return self._load_fallback_endpoints(prefix)

        if self._appconfig is None:
            self._appconfig = AzureAppConfigurationClient(
                base_url=endpoint, credential=self._credential
            )
        client = self._appconfig
        endpoints: list[dict] = []
        for item in client.list_configuration_settings(key_filter=f"{prefix}:*"):
            try:
                config = json.loads(item.value)
                config["key"] = item.key
            except (json.JSONDecodeError, TypeError) as e:
                logger.error("Invalid config for key '%s': %s", item.key, e)
                continue
            if _validate_endpoint(config, item.key):
                endpoints.append(config)
        return endpoints

    def _load_fallback_endpoints(self, prefix: str) -> list[dict]:
        """Load endpoints from a local JSON file as fallback."""
        fallback_path = os.path.join(
            os.path.dirname(__file__), "..", "config", "endpoints.json"
        )
        if not os.path.exists(fallback_path):
            logger.warning("No fallback endpoints.json found")
            return []

        try:
            with open(fallback_path) as f:
                all_endpoints = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            logger.error("Could not read fallback endpoints.json: %s", exc)
            return []

        frequency = prefix.split(":")[-1] if ":" in prefix else prefix
        raw_endpoints = all_endpoints.get(frequency, [])
        return [
            ep
            for ep in raw_endpoints
            if _validate_endpoint(
                ep, f"endpoints.json:{frequency}:{ep.get('key', ep.get('stream', '?'))}"
            )
        ]

    def _load_failed(self, schedule: str) -> list[tuple[float, dict]]:
        """Combine persisted + in-memory failed lists with TTL filter."""
        ttl = _ttl_seconds()
        persisted = self._store.load(schedule, ttl) if self._store.enabled else []
        now = time.time()
        memory = [
            (ts, ep)
            for ts, ep in self._memory_failed.get(schedule, [])
            if now - ts < ttl
        ]
        dropped = (
            len(self._memory_failed.get(schedule, [])) - len(memory)
            if not self._store.enabled
            else 0
        )
        if dropped:
            logger.warning(
                "%d previously failed %s endpoints expired (>%dh)",
                dropped,
                schedule,
                ttl // 3600,
            )
        return persisted + memory

    def _save_failed(self, schedule: str, failed: list[dict]) -> None:
        """Persist (or store in-memory) the new failed list for the next run."""
        now = time.time()
        if self._store.enabled:
            self._store.save(schedule, failed)
            # Keep in-memory empty to avoid duplicate retries.
            self._memory_failed[schedule] = []
        else:
            self._memory_failed[schedule] = [(now, ep) for ep in failed]

    async def _run_schedule(self, schedule: str) -> None:
        """Execute one polling run for a schedule (daily or weekly)."""
        run_id = uuid.uuid4().hex
        run_dims = {"schedule": schedule, "run_id": run_id}
        logger.info(
            "Start %s polling run", schedule, extra={"custom_dimensions": run_dims}
        )
        endpoints = self._load_endpoints(f"endpoints:{schedule}")

        retry_entries = self._load_failed(schedule)
        if retry_entries:
            logger.info(
                "Retrying %d previously failed %s endpoints",
                len(retry_entries),
                schedule,
            )
            endpoints = [ep for _, ep in retry_entries] + endpoints

        try:
            failed = await self._process_endpoints(
                endpoints, schedule=schedule, run_id=run_id
            )
        finally:
            await self._aclose_clients()
        # Write new failed-state ONLY after the run is fully complete.
        self._save_failed(schedule, failed)
        logger.info(
            "%s polling run completed",
            schedule.capitalize(),
            extra={"custom_dimensions": run_dims},
        )

    async def _aclose_clients(self) -> None:
        """Close any per-run async resources (HTTP sessions, ingestion client)."""
        for client in (self._defender, self._graph):
            close = getattr(client, "aclose", None)
            if close is not None:
                try:
                    await close()
                except Exception:  # noqa: BLE001
                    logger.debug("Error closing client %s", client, exc_info=True)

    async def run_daily(self) -> None:
        """Run all daily polls."""
        await self._run_schedule("daily")

    async def run_weekly(self) -> None:
        """Run all weekly polls."""
        await self._run_schedule("weekly")

    async def _process_endpoints(
        self, endpoints: list[dict], schedule: str, run_id: str
    ) -> list[dict]:
        """Process endpoints in parallel with bounded concurrency.

        Returns the list of endpoints that failed.
        """
        dcr_map = {
            "daily": os.environ.get("DCR_DAILY_SCORES_ID", ""),
            "weekly": os.environ.get("DCR_WEEKLY_SNAPSHOTS_ID", ""),
            "intune": os.environ.get("DCR_INTUNE_ID", ""),
        }
        concurrency = _concurrency_limit()
        semaphore = asyncio.Semaphore(concurrency)
        run_started = time.monotonic()

        logger.info(
            "Processing %d %s endpoints with concurrency=%d",
            len(endpoints),
            schedule,
            concurrency,
            extra={
                "custom_dimensions": {
                    "schedule": schedule,
                    "run_id": run_id,
                    "endpoint_count": len(endpoints),
                    "concurrency": concurrency,
                }
            },
        )

        async def _process_one(ep: dict) -> dict[str, Any]:
            async with semaphore:
                return await self._process_endpoint(ep, dcr_map, schedule, run_id)

        results = await asyncio.gather(*[_process_one(ep) for ep in endpoints])

        failed: list[dict] = []
        succeeded = 0
        empty = 0
        total_records = 0
        durations: list[float] = []
        for res in results:
            durations.append(res["duration"])
            status = res["status"]
            if status == "ok":
                succeeded += 1
                total_records += res["records"]
            elif status == "empty":
                empty += 1
            elif status == "failed":
                failed.append(res["endpoint"])

        summary: dict[str, Any] = {
            "schedule": schedule,
            "run_id": run_id,
            "total": len(endpoints),
            "succeeded": succeeded,
            "failed": len(failed),
            "empty": empty,
            "records_total": total_records,
            "concurrency": concurrency,
            "duration_seconds": round(time.monotonic() - run_started, 2),
            "duration_p50": round(_percentile(durations, 0.50), 3),
            "duration_p95": round(_percentile(durations, 0.95), 3),
            "failed_keys": [
                ep.get("key", ep.get("stream", "unknown")) for ep in failed
            ],
        }
        logger.info(
            "Polling summary (%s): %d/%d ok, %d failed, %d empty, %d records, %.1fs",
            summary["schedule"],
            summary["succeeded"],
            summary["total"],
            summary["failed"],
            summary["empty"],
            summary["records_total"],
            summary["duration_seconds"],
            extra={"custom_dimensions": summary},
        )
        if failed:
            logger.warning(
                "%d %s endpoints failed, will be retried next run",
                len(failed),
                schedule,
            )

        return failed

    async def _process_endpoint(
        self,
        ep: dict,
        dcr_map: dict[str, str],
        schedule: str,
        run_id: str,
    ) -> dict[str, Any]:
        """Fetch + ingest one endpoint. Returns a status dict for aggregation."""
        key = ep.get("key", ep.get("stream", "unknown"))
        started = time.monotonic()
        dims: dict[str, Any] = {
            "schedule": schedule,
            "run_id": run_id,
            "endpoint_key": key,
        }
        try:
            logger.info(
                "Processing endpoint: %s", key, extra={"custom_dimensions": dims}
            )
            dcr_kind = ep.get("dcr", "daily")
            dcr_id = dcr_map.get(dcr_kind, "")
            if not dcr_id:
                # Fail-fast: missing DCR-ID is a config error, not a silent skip.
                raise RuntimeError(
                    f"No DCR-ID configured for dcr='{dcr_kind}' "
                    f"(endpoint {key}); check appSettings/DCR_*_ID."
                )

            data = await self._fetch_data(ep)
            if not data:
                logger.warning(
                    "No data received for %s", key, extra={"custom_dimensions": dims}
                )
                return {
                    "status": "empty",
                    "endpoint": ep,
                    "duration": time.monotonic() - started,
                }

            stream = ep["stream"]
            await self._ingestion.upload(
                dcr_id=dcr_id,
                stream_name=stream,
                records=data,
                expected_columns=ep.get("expected_columns"),
            )
            duration = time.monotonic() - started
            logger.info(
                "Successfully ingested %d records for %s in %.2fs",
                len(data),
                key,
                duration,
                extra={
                    "custom_dimensions": {
                        **dims,
                        "records": len(data),
                        "duration_seconds": round(duration, 3),
                    }
                },
            )
            return {
                "status": "ok",
                "endpoint": ep,
                "records": len(data),
                "duration": duration,
            }

        except Exception:
            duration = time.monotonic() - started
            logger.exception(
                "Error processing endpoint %s",
                key,
                extra={
                    "custom_dimensions": {
                        **dims,
                        "duration_seconds": round(duration, 3),
                    }
                },
            )
            return {
                "status": "failed",
                "endpoint": ep,
                "duration": duration,
            }

    async def _fetch_data(self, endpoint: dict) -> list[dict]:
        """Fetch data via the appropriate client based on scope."""
        scope = endpoint.get("scope", "")
        url = endpoint["url"]
        transform = endpoint.get("transform", "list")
        raw: dict | list | None

        if transform == "advancedHunting":
            kql = endpoint.get("query", "")
            if not kql:
                logger.error("No 'query' field for advancedHunting endpoint %s", url)
                return []
            raw = await self._defender.run_advanced_query(kql)
            return self._transform(raw, transform)

        if "securitycenter.microsoft.com" in scope:
            raw = await self._defender.fetch(url)
        else:
            raw = await self._graph.fetch(url)

        return self._transform(raw, transform)

    def _transform(self, raw: dict | list | None, transform: str) -> list[dict]:
        """Transform an API response into a list of records."""
        if raw is None:
            return []

        if transform == "single":
            return [raw] if isinstance(raw, dict) else []

        if transform == "advancedHunting":
            if isinstance(raw, dict):
                return raw.get("Results", [])
            return []

        if transform in ("list", "graphList", "exportList"):
            if isinstance(raw, dict):
                return raw.get("value", [])
            return raw if isinstance(raw, list) else []

        logger.warning("Unknown transform type: %s", transform)
        return [raw] if isinstance(raw, dict) else []


def _percentile(values: list[float], pct: float) -> float:
    """Simple percentile computation without a numpy dependency."""
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(round(pct * (len(ordered) - 1))))
    return ordered[idx]

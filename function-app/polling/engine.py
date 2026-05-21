"""Config-driven polling engine.

Leest endpoint-configuratie uit Azure App Configuration en
orkestreert API-calls + data-ingestie.
Houdt mislukte endpoints bij voor retry in de volgende run (met TTL).
Persisteert die lijst in Azure Table Storage zodat een Flex Consumption
cold start de retry-state niet weggooit.
"""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any

from azure.appconfiguration import AzureAppConfigurationClient
from azure.identity import DefaultAzureCredential

from .defender_client import DefenderClient
from .graph_client import GraphClient
from .ingestion import IngestionClient
from .state_store import FailedEndpointStore

logger = logging.getLogger(__name__)


def _ttl_seconds() -> int:
    """Failed-endpoint TTL, configureerbaar via FAILED_ENDPOINT_TTL_HOURS."""
    raw = os.environ.get("FAILED_ENDPOINT_TTL_HOURS", "24")
    try:
        hours = int(raw)
    except ValueError:
        hours = 24
    return max(1, hours) * 3600


class PollingEngine:
    """Orkestreert het ophalen van API-data en de ingestie naar Log Analytics."""

    def __init__(self) -> None:
        self._credential = DefaultAzureCredential()
        self._defender = DefenderClient(self._credential)
        self._graph = GraphClient(self._credential)
        self._ingestion = IngestionClient(self._credential)
        self._store = FailedEndpointStore(self._credential)
        # In-memory fallback wanneer Table Storage niet beschikbaar is.
        self._memory_failed: dict[str, list[tuple[float, dict]]] = {
            "daily": [],
            "weekly": [],
        }

    def _load_endpoints(self, prefix: str) -> list[dict]:
        """Laad endpoint-configuratie uit App Configuration.

        Args:
            prefix: Key prefix filter (bijv. 'endpoints:daily' of 'endpoints:weekly').

        Returns:
            Lijst van endpoint-configuratie dictionaries.
        """
        endpoint = os.environ.get("APP_CONFIG_ENDPOINT", "")
        if not endpoint:
            logger.warning("APP_CONFIG_ENDPOINT niet geconfigureerd, gebruik fallback")
            return self._load_fallback_endpoints(prefix)

        client = AzureAppConfigurationClient(
            base_url=endpoint, credential=self._credential
        )
        endpoints: list[dict] = []
        for item in client.list_configuration_settings(key_filter=f"{prefix}:*"):
            try:
                config = json.loads(item.value)
                config["key"] = item.key
                endpoints.append(config)
            except (json.JSONDecodeError, TypeError) as e:
                logger.error("Ongeldige config voor key '%s': %s", item.key, e)
        return endpoints

    def _load_fallback_endpoints(self, prefix: str) -> list[dict]:
        """Laad endpoints uit lokaal JSON-bestand als fallback."""
        fallback_path = os.path.join(
            os.path.dirname(__file__), "..", "config", "endpoints.json"
        )
        if not os.path.exists(fallback_path):
            logger.warning("Geen fallback endpoints.json gevonden")
            return []

        try:
            with open(fallback_path) as f:
                all_endpoints = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            logger.error("Kon fallback endpoints.json niet lezen: %s", exc)
            return []

        frequency = prefix.split(":")[-1] if ":" in prefix else prefix
        return all_endpoints.get(frequency, [])

    def _load_failed(self, schedule: str) -> list[tuple[float, dict]]:
        """Combineer persisted + in-memory failed-lijsten met TTL-filter."""
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
                "%d eerder mislukte %s endpoints verlopen (>%dh)",
                dropped,
                schedule,
                ttl // 3600,
            )
        return persisted + memory

    def _save_failed(self, schedule: str, failed: list[dict]) -> None:
        """Persisteer (of in-memory) de nieuwe failed-lijst voor volgende run."""
        now = time.time()
        if self._store.enabled:
            self._store.save(schedule, failed)
            # Houd in-memory leeg om dubbele retries te voorkomen.
            self._memory_failed[schedule] = []
        else:
            self._memory_failed[schedule] = [(now, ep) for ep in failed]

    async def _run_schedule(self, schedule: str) -> None:
        """Voer één polling-run uit voor een schedule (daily of weekly)."""
        logger.info("Start %s polling run", schedule)
        endpoints = self._load_endpoints(f"endpoints:{schedule}")

        retry_entries = self._load_failed(schedule)
        if retry_entries:
            logger.info(
                "Retry %d eerder mislukte %s endpoints",
                len(retry_entries),
                schedule,
            )
            endpoints = [ep for _, ep in retry_entries] + endpoints

        failed = await self._process_endpoints(endpoints, schedule=schedule)
        # Schrijf nieuwe failed-state PAS na voltooiing van de run.
        self._save_failed(schedule, failed)
        logger.info("%s polling run voltooid", schedule.capitalize())

    async def run_daily(self) -> None:
        """Voer alle dagelijkse polls uit."""
        await self._run_schedule("daily")

    async def run_weekly(self) -> None:
        """Voer alle wekelijkse polls uit."""
        await self._run_schedule("weekly")

    async def _process_endpoints(
        self, endpoints: list[dict], schedule: str
    ) -> list[dict]:
        """Verwerk een lijst endpoints: ophalen + ingestie. Retourneert mislukte endpoints."""
        dcr_map = {
            "daily": os.environ.get("DCR_DAILY_SCORES_ID", ""),
            "weekly": os.environ.get("DCR_WEEKLY_SNAPSHOTS_ID", ""),
            "intune": os.environ.get("DCR_INTUNE_ID", ""),
        }
        failed: list[dict] = []
        succeeded = 0
        empty = 0
        total_records = 0
        durations: list[float] = []
        run_started = time.monotonic()

        for ep in endpoints:
            key = ep.get("key", ep.get("stream", "unknown"))
            ep_started = time.monotonic()
            try:
                logger.info("Verwerk endpoint: %s", key)
                dcr_kind = ep.get("dcr", "daily")
                dcr_id = dcr_map.get(dcr_kind, "")
                if not dcr_id:
                    # Fail-fast: ontbrekende DCR-ID is een configuratiefout, geen silent skip.
                    raise RuntimeError(
                        f"Geen DCR-ID geconfigureerd voor dcr='{dcr_kind}' "
                        f"(endpoint {key}); check appSettings/DCR_*_ID."
                    )

                data = await self._fetch_data(ep)
                if not data:
                    logger.warning("Geen data ontvangen voor %s", key)
                    empty += 1
                    continue

                stream = ep["stream"]
                self._ingestion.upload(
                    dcr_id=dcr_id,
                    stream_name=stream,
                    records=data,
                    expected_columns=ep.get("expected_columns"),
                )
                succeeded += 1
                total_records += len(data)
                logger.info("Succesvol %d records geïngest voor %s", len(data), key)

            except Exception:
                logger.exception("Fout bij verwerken van endpoint %s", key)
                failed.append(ep)
            finally:
                durations.append(time.monotonic() - ep_started)

        # Aggregate summary log met custom dimensions voor App Insights.
        summary: dict[str, Any] = {
            "schedule": schedule,
            "total": len(endpoints),
            "succeeded": succeeded,
            "failed": len(failed),
            "empty": empty,
            "records_total": total_records,
            "duration_seconds": round(time.monotonic() - run_started, 2),
            "duration_p50": round(_percentile(durations, 0.50), 3),
            "duration_p95": round(_percentile(durations, 0.95), 3),
            "failed_keys": [
                ep.get("key", ep.get("stream", "unknown")) for ep in failed
            ],
        }
        logger.info(
            "Polling samenvatting (%s): %d/%d gelukt, %d gefaald, %d leeg, %d records, %.1fs",
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
                "%d %s endpoints mislukt, worden volgende run opnieuw geprobeerd",
                len(failed),
                schedule,
            )

        return failed

    async def _fetch_data(self, endpoint: dict) -> list[dict]:
        """Haal data op via de juiste client op basis van scope."""
        scope = endpoint.get("scope", "")
        url = endpoint["url"]
        transform = endpoint.get("transform", "list")
        raw: dict | list | None

        if transform == "advancedHunting":
            kql = endpoint.get("query", "")
            if not kql:
                logger.error("Geen 'query' veld voor advancedHunting endpoint %s", url)
                return []
            raw = await self._defender.run_advanced_query(kql)
            return self._transform(raw, transform)

        if "securitycenter.microsoft.com" in scope:
            raw = await self._defender.fetch(url)
        else:
            raw = await self._graph.fetch(url)

        return self._transform(raw, transform)

    def _transform(self, raw: dict | list | None, transform: str) -> list[dict]:
        """Transformeer API response naar lijst van records."""
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

        logger.warning("Onbekend transform type: %s", transform)
        return [raw] if isinstance(raw, dict) else []


def _percentile(values: list[float], pct: float) -> float:
    """Simpele percentiel-berekening zonder numpy-afhankelijkheid."""
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(round(pct * (len(ordered) - 1))))
    return ordered[idx]

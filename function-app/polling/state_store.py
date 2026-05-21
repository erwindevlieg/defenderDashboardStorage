"""Persistent storage for failed endpoints (per schedule).

Flex Consumption is stateless; without persistent storage we would lose the
retry list on every cold start. This module writes failed endpoints to an
Azure Storage Table and reads them back at the beginning of a run.

Best-effort: on any table error the engine falls back to in-memory state so
the polling function keeps running.
"""

from __future__ import annotations

import contextlib
import json
import logging
import os
import random
import time
import uuid
from collections.abc import Callable
from typing import Any, TypeVar

from azure.core.credentials import TokenCredential

logger = logging.getLogger(__name__)

_T = TypeVar("_T")

# Small retry budget for transient table-storage failures. Operations are
# best-effort; on exhaustion the engine falls back to in-memory state.
_TABLE_RETRY_ATTEMPTS = 3
_TABLE_RETRY_BASE_DELAY = 0.5  # seconds


def _with_retry(operation: str, func: Callable[[], _T]) -> _T | None:
    """Call ``func`` with bounded exponential backoff on transient errors.

    Returns the function result on success, or None when the retry budget is
    exhausted. Each attempt is logged at debug level; the final failure logs a
    warning so it shows up in App Insights without becoming alert-noise.
    """
    last_exc: BaseException | None = None
    for attempt in range(1, _TABLE_RETRY_ATTEMPTS + 1):
        try:
            return func()
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            if attempt == _TABLE_RETRY_ATTEMPTS:
                break
            delay = _TABLE_RETRY_BASE_DELAY * (2 ** (attempt - 1)) + random.uniform(
                0.0, 0.25
            )
            logger.debug(
                "Table op %s failed (attempt %d/%d): %s; retrying in %.2fs",
                operation,
                attempt,
                _TABLE_RETRY_ATTEMPTS,
                exc,
                delay,
            )
            time.sleep(delay)
    logger.warning(
        "Table op %s exhausted retries (%d attempts): %s",
        operation,
        _TABLE_RETRY_ATTEMPTS,
        last_exc,
    )
    return None


# One TableClient per (account, table) is cached to avoid reconnect cost
# within a single Function-host instance.
_TABLE_CLIENT_CACHE: dict[tuple[str, str], object] = {}


def _build_table_client(
    credential: TokenCredential, account_name: str, table_name: str
) -> object | None:
    """Build (or return cached) TableClient. Returns None on error."""
    key = (account_name, table_name)
    if key in _TABLE_CLIENT_CACHE:
        return _TABLE_CLIENT_CACHE[key]

    try:
        from azure.data.tables import TableClient
    except ImportError:
        logger.warning("azure-data-tables not installed; persistent state disabled")
        return None

    try:
        endpoint = f"https://{account_name}.table.core.windows.net"
        client = TableClient(
            endpoint=endpoint, table_name=table_name, credential=credential
        )
        # Ensure the table exists (idempotent — SDK raises ResourceExistsError).
        with contextlib.suppress(Exception):
            client.create_table()
        _TABLE_CLIENT_CACHE[key] = client
        return client
    except Exception as exc:  # noqa: BLE001
        logger.warning("Could not build TableClient: %s", exc)
        return None


class FailedEndpointStore:
    """Persists failed endpoints in Azure Table Storage.

    Entity schema:
      - PartitionKey: ``<schedule>`` for retry-eligible entries, or
        ``poison-<schedule>`` for endpoints that have exceeded
        ``MAX_POISON_ATTEMPTS``.
      - RowKey: unique id (uuid4)
      - Timestamp: set by SDK
      - QueuedAt: epoch seconds the endpoint last failed (float)
      - AttemptCount: number of consecutive failed attempts (int, default 0
        for legacy rows written before B3)
      - Endpoint: JSON-serialized endpoint config (string)
    """

    def __init__(
        self,
        credential: TokenCredential,
        account_name: str | None = None,
        table_name: str | None = None,
    ) -> None:
        self._credential = credential
        self._account: str = (
            account_name or os.environ.get("STATE_STORAGE_ACCOUNT") or ""
        )
        self._table: str = (
            table_name or os.environ.get("STATE_TABLE_NAME") or "FailedEndpoints"
        )
        self._client = (
            _build_table_client(credential, self._account, self._table)
            if self._account
            else None
        )

    @property
    def enabled(self) -> bool:
        """Return whether persistence is active (Table client built successfully)."""
        return self._client is not None

    @staticmethod
    def _poison_partition(schedule: str) -> str:
        return f"poison-{schedule}"

    def load(self, schedule: str, ttl_seconds: int) -> list[tuple[float, dict, int]]:
        """Load all non-expired failed entries for a schedule.

        Each tuple is ``(queued_at, endpoint, attempt_count)``. Expired
        entries are deleted in-line. On error: log and return [].
        """
        if not self._client:
            return []

        now = time.time()
        result: list[tuple[float, dict, int]] = []

        def _query() -> Any:
            return list(
                self._client.query_entities(  # type: ignore[attr-defined]
                    query_filter="PartitionKey eq @s",
                    parameters={"s": schedule},
                )
            )

        entities = _with_retry(f"load {schedule}", _query)
        if entities is None:
            return []

        for entity in entities:
            try:
                queued_at = float(entity.get("QueuedAt", 0.0))
                endpoint = json.loads(entity.get("Endpoint", "{}"))
                attempt_count = int(entity.get("AttemptCount", 0) or 0)
            except (TypeError, ValueError, json.JSONDecodeError):
                logger.warning("Skipping invalid failed-entry %s", entity.get("RowKey"))
                self._safe_delete(schedule, entity.get("RowKey", ""))
                continue

            if now - queued_at >= ttl_seconds:
                self._safe_delete(schedule, entity.get("RowKey", ""))
                continue

            result.append((queued_at, endpoint, attempt_count))

        return result

    def clear(self, schedule: str) -> None:
        """Delete all entries for a schedule (after a successful reload)."""
        if not self._client:
            return

        def _query() -> Any:
            return list(
                self._client.query_entities(  # type: ignore[attr-defined]
                    query_filter="PartitionKey eq @s",
                    parameters={"s": schedule},
                    select=["PartitionKey", "RowKey"],
                )
            )

        entities = _with_retry(f"clear {schedule}", _query)
        if entities is None:
            return
        for entity in entities:
            self._safe_delete(schedule, entity.get("RowKey", ""))

    def save(
        self,
        schedule: str,
        failed: list[dict] | list[tuple[dict, int]],
    ) -> None:
        """Write the current failed-set (overwrites the previous one).

        Accepts either a plain list of endpoint dicts (legacy callers,
        attempt count defaults to 1) or a list of ``(endpoint, attempt_count)``
        tuples.
        """
        if not self._client:
            return
        self.clear(schedule)
        now = time.time()
        for entry in failed:
            if isinstance(entry, tuple):
                ep, attempt_count = entry
            else:
                ep, attempt_count = entry, 1
            entity = {
                "PartitionKey": schedule,
                "RowKey": uuid.uuid4().hex,
                "QueuedAt": now,
                "AttemptCount": int(attempt_count),
                "Endpoint": json.dumps(ep, default=str),
            }

            def _create(e: dict = entity) -> Any:
                return self._client.create_entity(e)  # type: ignore[attr-defined]

            _with_retry("create_entity", _create)

    def save_poisoned(self, schedule: str, endpoint: dict, attempt_count: int) -> None:
        """Persist an endpoint that has exceeded the poison threshold.

        Written to a dedicated ``poison-<schedule>`` partition so the retry
        loop never picks it up again. Operators triage via Storage Explorer
        / KQL alert (see B4).
        """
        if not self._client:
            return
        entity = {
            "PartitionKey": self._poison_partition(schedule),
            "RowKey": uuid.uuid4().hex,
            "QueuedAt": time.time(),
            "AttemptCount": int(attempt_count),
            "Endpoint": json.dumps(endpoint, default=str),
        }

        def _create() -> Any:
            return self._client.create_entity(entity)  # type: ignore[attr-defined]

        _with_retry("create_poisoned", _create)

    def _safe_delete(self, partition_key: str, row_key: str) -> None:
        if not self._client or not row_key:
            return
        # Best-effort: delete may already have happened / entry may be gone.
        with contextlib.suppress(Exception):
            self._client.delete_entity(  # type: ignore[attr-defined]
                partition_key=partition_key, row_key=row_key
            )

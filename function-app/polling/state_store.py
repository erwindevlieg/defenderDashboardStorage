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
import time
import uuid

from azure.core.credentials import TokenCredential

logger = logging.getLogger(__name__)

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
      - PartitionKey: schedule ('daily' / 'weekly')
      - RowKey: unique id (uuid4)
      - Timestamp: set by SDK
      - QueuedAt: epoch seconds the endpoint failed (float)
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

    def load(self, schedule: str, ttl_seconds: int) -> list[tuple[float, dict]]:
        """Load all non-expired failed entries for a schedule.

        Expired entries are deleted in-line. On error: log and return [].
        """
        if not self._client:
            return []

        now = time.time()
        result: list[tuple[float, dict]] = []
        try:
            entities = self._client.query_entities(  # type: ignore[attr-defined]
                query_filter="PartitionKey eq @s",
                parameters={"s": schedule},
            )
            for entity in entities:
                try:
                    queued_at = float(entity.get("QueuedAt", 0.0))
                    endpoint = json.loads(entity.get("Endpoint", "{}"))
                except (TypeError, ValueError, json.JSONDecodeError):
                    logger.warning(
                        "Skipping invalid failed-entry %s", entity.get("RowKey")
                    )
                    self._safe_delete(schedule, entity.get("RowKey", ""))
                    continue

                if now - queued_at >= ttl_seconds:
                    self._safe_delete(schedule, entity.get("RowKey", ""))
                    continue

                result.append((queued_at, endpoint))
        except Exception as exc:  # noqa: BLE001
            logger.warning("Could not load failed-state (%s): %s", schedule, exc)
            return []

        return result

    def clear(self, schedule: str) -> None:
        """Delete all entries for a schedule (after a successful reload)."""
        if not self._client:
            return
        try:
            entities = self._client.query_entities(  # type: ignore[attr-defined]
                query_filter="PartitionKey eq @s",
                parameters={"s": schedule},
                select=["PartitionKey", "RowKey"],
            )
            for entity in entities:
                self._safe_delete(schedule, entity.get("RowKey", ""))
        except Exception as exc:  # noqa: BLE001
            logger.warning("Could not clear failed-state (%s): %s", schedule, exc)

    def save(self, schedule: str, failed: list[dict]) -> None:
        """Write the current failed-set (overwrites the previous one)."""
        if not self._client:
            return
        self.clear(schedule)
        now = time.time()
        for ep in failed:
            try:
                self._client.create_entity(  # type: ignore[attr-defined]
                    {
                        "PartitionKey": schedule,
                        "RowKey": uuid.uuid4().hex,
                        "QueuedAt": now,
                        "Endpoint": json.dumps(ep, default=str),
                    }
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning("Could not save failed-entry: %s", exc)

    def _safe_delete(self, partition_key: str, row_key: str) -> None:
        if not self._client or not row_key:
            return
        # Best-effort: delete may already have happened / entry may be gone.
        with contextlib.suppress(Exception):
            self._client.delete_entity(  # type: ignore[attr-defined]
                partition_key=partition_key, row_key=row_key
            )

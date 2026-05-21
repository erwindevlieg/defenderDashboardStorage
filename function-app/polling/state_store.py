"""Persistente opslag van mislukte endpoints (per schedule).

Flex Consumption is stateless; zonder persistente opslag verliezen we de
retry-lijst bij elke cold start. Deze module schrijft mislukte endpoints
naar een Azure Storage Table en leest ze terug bij start van een run.

Best-effort: bij elke tabel-fout valt de engine terug op in-memory state,
zodat de polling-functie blijft draaien.
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

# Eén TableClient per (account, table) wordt gecached om reconnect-kosten te
# vermijden binnen één Function-host instance.
_TABLE_CLIENT_CACHE: dict[tuple[str, str], object] = {}


def _build_table_client(
    credential: TokenCredential, account_name: str, table_name: str
) -> object | None:
    """Maak (of haal uit cache) een TableClient. Retourneert None bij fouten."""
    key = (account_name, table_name)
    if key in _TABLE_CLIENT_CACHE:
        return _TABLE_CLIENT_CACHE[key]

    try:
        from azure.data.tables import TableClient
    except ImportError:
        logger.warning(
            "azure-data-tables niet geïnstalleerd; persistente state uitgeschakeld"
        )
        return None

    try:
        endpoint = f"https://{account_name}.table.core.windows.net"
        client = TableClient(
            endpoint=endpoint, table_name=table_name, credential=credential
        )
        # Zorg dat de tabel bestaat (idempotent — SDK gooit ResourceExistsError).
        with contextlib.suppress(Exception):
            client.create_table()
        _TABLE_CLIENT_CACHE[key] = client
        return client
    except Exception as exc:  # noqa: BLE001
        logger.warning("Kon TableClient niet maken: %s", exc)
        return None


class FailedEndpointStore:
    """Persisteert mislukte endpoints in Azure Table Storage.

    Schema per entity:
      - PartitionKey: schedule ('daily' / 'weekly')
      - RowKey: unieke ID (uuid4)
      - Timestamp: door SDK gezet
      - QueuedAt: epoch seconden waarop endpoint gefaald is (float)
      - Endpoint: JSON-serialized endpoint-config (string)
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
        """Laad alle niet-verlopen failed entries voor een schedule.

        Verlopen entries worden direct verwijderd.
        Bij fouten: log + return [].
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
                        "Ongeldige failed-entry %s overgeslagen", entity.get("RowKey")
                    )
                    self._safe_delete(schedule, entity.get("RowKey", ""))
                    continue

                if now - queued_at >= ttl_seconds:
                    self._safe_delete(schedule, entity.get("RowKey", ""))
                    continue

                result.append((queued_at, endpoint))
        except Exception as exc:  # noqa: BLE001
            logger.warning("Kon failed-state niet laden (%s): %s", schedule, exc)
            return []

        return result

    def clear(self, schedule: str) -> None:
        """Verwijder alle entries voor een schedule (na succesvolle reload)."""
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
            logger.warning("Kon failed-state niet wissen (%s): %s", schedule, exc)

    def save(self, schedule: str, failed: list[dict]) -> None:
        """Schrijf de huidige failed-set weg (overschrijft de vorige)."""
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
                logger.warning("Kon failed-entry niet opslaan: %s", exc)

    def _safe_delete(self, partition_key: str, row_key: str) -> None:
        if not self._client or not row_key:
            return
        # Best-effort: verwijdering kan al gebeurd zijn / entry kan verdwenen zijn.
        with contextlib.suppress(Exception):
            self._client.delete_entity(  # type: ignore[attr-defined]
                partition_key=partition_key, row_key=row_key
            )

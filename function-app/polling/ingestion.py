"""LogsIngestionClient wrapper met batching, retry en schema-validatie.

Schrijft records naar Log Analytics via de Logs Ingestion API (DCR/DCE).
"""

from __future__ import annotations

import logging
import os
from collections.abc import Iterable

from azure.core.credentials import TokenCredential
from azure.monitor.ingestion import LogsIngestionClient as AzureLogsIngestionClient

logger = logging.getLogger(__name__)

# Logs Ingestion API max payload: 1 MB
MAX_BATCH_SIZE_BYTES = 1_000_000


class SchemaValidationError(ValueError):
    """Wordt opgegooid bij schema-mismatch in strict-mode."""


def _validate_records(
    records: list[dict],
    expected_columns: Iterable[str] | None,
    stream_name: str,
    strict: bool,
) -> list[dict]:
    """Valideer records tegen `expected_columns`.

    - Lenient (default): onbekende kolommen worden weggefilterd; loggt waarschuwing per run.
    - Strict: gooit SchemaValidationError bij eerste mismatch.

    Geeft de (eventueel gefilterde) records terug.
    """
    if not expected_columns:
        return records

    expected = set(expected_columns)
    unexpected: set[str] = set()
    cleaned: list[dict] = []
    for record in records:
        extras = set(record.keys()) - expected
        if extras:
            unexpected.update(extras)
            if strict:
                raise SchemaValidationError(
                    f"Onverwachte kolommen in stream {stream_name}: {sorted(extras)}"
                )
            filtered = {k: v for k, v in record.items() if k in expected}
            if filtered:
                cleaned.append(filtered)
        else:
            cleaned.append(record)

    if unexpected:
        logger.warning(
            "Schema-mismatch voor stream %s: %d onverwachte kolommen weggefilterd: %s",
            stream_name,
            len(unexpected),
            sorted(unexpected),
        )
    return cleaned


class IngestionClient:
    """Wrapper rond azure-monitor-ingestion SDK."""

    def __init__(self, credential: TokenCredential) -> None:
        dce_endpoint = os.environ.get("DCE_ENDPOINT", "")
        if not dce_endpoint:
            raise ValueError("DCE_ENDPOINT environment variable is niet geconfigureerd")

        self._client = AzureLogsIngestionClient(
            endpoint=dce_endpoint,
            credential=credential,
            logging_enable=False,
        )
        self._strict = (
            os.environ.get("INGESTION_STRICT_SCHEMA", "false").lower() == "true"
        )

    def upload(
        self,
        dcr_id: str,
        stream_name: str,
        records: list[dict],
        expected_columns: Iterable[str] | None = None,
    ) -> None:
        """Upload records naar Log Analytics via de Logs Ingestion API.

        Voert optioneel schema-validatie uit voor upload (lenient/strict).

        Args:
            dcr_id: Immutable ID van de Data Collection Rule.
            stream_name: Naam van de stream (bijv. 'Custom-DefenderExposureScore_CL').
            records: Lijst van records om te uploaden.
            expected_columns: Optionele whitelist van toegestane kolommen.

        Raises:
            SchemaValidationError: Bij schema-mismatch in strict-mode.
            Exception: Bij onherstelbare upload-fouten.
        """
        if not records:
            logger.debug("Geen records om te uploaden voor stream %s", stream_name)
            return

        if not dcr_id:
            # Engine valideert dit al; hier is het een echte programmeerfout.
            raise ValueError(
                f"Lege DCR-ID doorgegeven aan upload() voor stream {stream_name}"
            )

        records = _validate_records(
            records, expected_columns, stream_name, self._strict
        )

        if not records:
            logger.warning(
                "Geen records over na schema-validatie voor stream %s", stream_name
            )
            return

        logger.info(
            "Upload %d records naar stream %s (DCR: %s)",
            len(records),
            stream_name,
            dcr_id[:20] + "...",
        )

        try:
            self._client.upload(
                rule_id=dcr_id,
                stream_name=stream_name,
                logs=list(records),
            )
            logger.info(
                "Upload succesvol: %d records naar %s", len(records), stream_name
            )
        except Exception:
            logger.error(
                "Upload mislukt voor stream %s (%d records)", stream_name, len(records)
            )
            raise

    def close(self) -> None:
        """Sluit de underlying client."""
        self._client.close()

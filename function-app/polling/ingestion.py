"""LogsIngestionClient wrapper with batching, retry and schema validation.

Writes records to Log Analytics via the Logs Ingestion API (DCR/DCE).
"""

from __future__ import annotations

import logging
import os
from collections.abc import Iterable

from azure.core.credentials_async import AsyncTokenCredential
from azure.monitor.ingestion.aio import (
    LogsIngestionClient as AzureLogsIngestionClient,
)

logger = logging.getLogger(__name__)


class SchemaValidationError(ValueError):
    """Raised on schema mismatch in strict mode."""


def _validate_records(
    records: list[dict],
    expected_columns: Iterable[str] | None,
    stream_name: str,
    strict: bool,
) -> list[dict]:
    """Validate records against ``expected_columns``.

    - Lenient (default): unknown columns are dropped; logs a warning per run.
    - Strict: raises SchemaValidationError on the first mismatch.

    Returns the (possibly filtered) records.
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
                    f"Unexpected columns in stream {stream_name}: {sorted(extras)}"
                )
            filtered = {k: v for k, v in record.items() if k in expected}
            if filtered:
                cleaned.append(filtered)
        else:
            cleaned.append(record)

    if unexpected:
        logger.warning(
            "Schema mismatch for stream %s: %d unexpected columns dropped: %s",
            stream_name,
            len(unexpected),
            sorted(unexpected),
        )
    return cleaned


class IngestionClient:
    """Wrapper around the azure-monitor-ingestion async SDK."""

    def __init__(self, credential: AsyncTokenCredential) -> None:
        dce_endpoint = os.environ.get("DCE_ENDPOINT", "")
        if not dce_endpoint:
            raise ValueError("DCE_ENDPOINT environment variable is not configured")

        self._client = AzureLogsIngestionClient(
            endpoint=dce_endpoint,
            credential=credential,
            logging_enable=False,
        )
        self._strict = (
            os.environ.get("INGESTION_STRICT_SCHEMA", "false").lower() == "true"
        )

    async def upload(
        self,
        dcr_id: str,
        stream_name: str,
        records: list[dict],
        expected_columns: Iterable[str] | None = None,
    ) -> None:
        """Upload records to Log Analytics via the Logs Ingestion API.

        Optionally performs schema validation before upload (lenient/strict).

        Args:
            dcr_id: Immutable ID of the Data Collection Rule.
            stream_name: Stream name (e.g. 'Custom-DefenderExposureScore_CL').
            records: List of records to upload.
            expected_columns: Optional whitelist of allowed columns.

        Raises:
            SchemaValidationError: On schema mismatch in strict mode.
            Exception: On unrecoverable upload errors.
        """
        if not records:
            logger.debug("No records to upload for stream %s", stream_name)
            return

        if not dcr_id:
            # Engine already validates this; here it would be a real programming error.
            raise ValueError(
                f"Empty DCR-ID passed to upload() for stream {stream_name}"
            )

        records = _validate_records(
            records, expected_columns, stream_name, self._strict
        )

        if not records:
            logger.warning(
                "No records left after schema validation for stream %s", stream_name
            )
            return

        logger.info(
            "Uploading %d records to stream %s (DCR: %s)",
            len(records),
            stream_name,
            dcr_id[:20] + "...",
        )

        try:
            await self._client.upload(
                rule_id=dcr_id,
                stream_name=stream_name,
                logs=list(records),
            )
            logger.info(
                "Upload successful: %d records to %s", len(records), stream_name
            )
        except Exception:
            logger.error(
                "Upload failed for stream %s (%d records)", stream_name, len(records)
            )
            raise

    async def aclose(self) -> None:
        """Close the underlying async client."""
        await self._client.close()

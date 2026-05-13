"""LogsIngestionClient wrapper met batching en retry.

Schrijft records naar Log Analytics via de Logs Ingestion API (DCR/DCE).
"""

import logging
import os

from azure.identity import DefaultAzureCredential
from azure.monitor.ingestion import LogsIngestionClient as AzureLogsIngestionClient

logger = logging.getLogger(__name__)

# Logs Ingestion API max payload: 1 MB
MAX_BATCH_SIZE_BYTES = 1_000_000


class IngestionClient:
    """Wrapper rond azure-monitor-ingestion SDK."""

    def __init__(self, credential: DefaultAzureCredential) -> None:
        dce_endpoint = os.environ.get("DCE_ENDPOINT", "")
        if not dce_endpoint:
            raise ValueError("DCE_ENDPOINT environment variable is niet geconfigureerd")

        self._client = AzureLogsIngestionClient(
            endpoint=dce_endpoint,
            credential=credential,
            logging_enable=False,
        )

    def upload(
        self,
        dcr_id: str,
        stream_name: str,
        records: list[dict],
    ) -> None:
        """Upload records naar Log Analytics via de Logs Ingestion API.

        De SDK handelt automatisch batching, compression en retry af.

        Args:
            dcr_id: Immutable ID van de Data Collection Rule.
            stream_name: Naam van de stream (bijv. 'Custom-DefenderExposureScore_CL').
            records: Lijst van records om te uploaden.

        Raises:
            Exception: Bij onherstelbare upload-fouten.
        """
        if not records:
            logger.debug("Geen records om te uploaden voor stream %s", stream_name)
            return

        if not dcr_id:
            logger.error("Geen DCR ID geconfigureerd voor stream %s", stream_name)
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
                logs=records,
            )
            logger.info(
                "Upload succesvol: %d records naar %s", len(records), stream_name
            )
        except Exception:
            logger.exception(
                "Upload mislukt voor stream %s (%d records)", stream_name, len(records)
            )
            raise

    def close(self) -> None:
        """Sluit de underlying client."""
        self._client.close()

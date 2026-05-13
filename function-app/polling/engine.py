"""Config-driven polling engine.

Leest endpoint-configuratie uit Azure App Configuration en
orkestreert API-calls + data-ingestie.
"""

import json
import logging
import os

from azure.appconfiguration import AzureAppConfigurationClient
from azure.identity import DefaultAzureCredential

from .defender_client import DefenderClient
from .graph_client import GraphClient
from .ingestion import IngestionClient

logger = logging.getLogger(__name__)


class PollingEngine:
    """Orkestreert het ophalen van API-data en de ingestie naar Log Analytics."""

    def __init__(self) -> None:
        self._credential = DefaultAzureCredential()
        self._defender = DefenderClient(self._credential)
        self._graph = GraphClient(self._credential)
        self._ingestion = IngestionClient(self._credential)

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
        endpoints = []
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

        with open(fallback_path) as f:
            all_endpoints = json.load(f)

        frequency = prefix.split(":")[-1] if ":" in prefix else prefix
        return all_endpoints.get(frequency, [])

    async def run_daily(self) -> None:
        """Voer alle dagelijkse polls uit."""
        logger.info("Start dagelijkse polling run")
        endpoints = self._load_endpoints("endpoints:daily")
        await self._process_endpoints(endpoints)
        logger.info("Dagelijkse polling run voltooid")

    async def run_weekly(self) -> None:
        """Voer alle wekelijkse polls uit (inclusief Intune)."""
        logger.info("Start wekelijkse polling run")
        weekly = self._load_endpoints("endpoints:weekly")
        await self._process_endpoints(weekly)
        logger.info("Wekelijkse polling run voltooid")

    async def _process_endpoints(self, endpoints: list[dict]) -> None:
        """Verwerk een lijst endpoints: ophalen + ingestie."""
        dcr_map = {
            "daily": os.environ.get("DCR_DAILY_SCORES_ID", ""),
            "weekly": os.environ.get("DCR_WEEKLY_SNAPSHOTS_ID", ""),
            "intune": os.environ.get("DCR_INTUNE_ID", ""),
        }

        for ep in endpoints:
            key = ep.get("key", ep.get("stream", "unknown"))
            try:
                logger.info("Verwerk endpoint: %s", key)
                data = await self._fetch_data(ep)
                if not data:
                    logger.warning("Geen data ontvangen voor %s", key)
                    continue

                dcr_id = dcr_map.get(ep.get("dcr", "daily"), "")
                stream = ep["stream"]
                self._ingestion.upload(dcr_id=dcr_id, stream_name=stream, records=data)
                logger.info("Succesvol %d records geïngest voor %s", len(data), key)

            except Exception:
                logger.error("Fout bij verwerken van endpoint %s", key)

    async def _fetch_data(self, endpoint: dict) -> list[dict]:
        """Haal data op via de juiste client op basis van scope."""
        scope = endpoint.get("scope", "")
        url = endpoint["url"]
        transform = endpoint.get("transform", "list")

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
            # Enkel object (bijv. Exposure Score)
            return [raw] if isinstance(raw, dict) else []

        if transform == "list":
            # Defender-stijl: { "value": [...] }
            if isinstance(raw, dict):
                return raw.get("value", [])
            return raw if isinstance(raw, list) else []

        if transform == "graphList":
            # Graph-stijl: { "value": [...] } met @odata.nextLink
            if isinstance(raw, dict):
                return raw.get("value", [])
            return raw if isinstance(raw, list) else []

        if transform == "exportList":
            # Export API: { "value": [...] } met paginering
            if isinstance(raw, dict):
                return raw.get("value", [])
            return raw if isinstance(raw, list) else []

        logger.warning("Onbekend transform type: %s", transform)
        return [raw] if isinstance(raw, dict) else []

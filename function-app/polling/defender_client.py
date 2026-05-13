"""Defender for Endpoint API client.

Gebruikt Managed Identity voor authenticatie tegen
https://api.securitycenter.microsoft.com.
"""

import logging

import aiohttp
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

DEFENDER_SCOPE = "https://api.securitycenter.microsoft.com/.default"


class DefenderClient:
    """Client voor Microsoft Defender for Endpoint REST API."""

    def __init__(self, credential: DefaultAzureCredential) -> None:
        self._credential = credential

    def _get_token(self) -> str:
        """Verkrijg een Bearer token voor de Defender API."""
        token = self._credential.get_token(DEFENDER_SCOPE)
        return token.token

    async def fetch(self, url: str) -> dict | list | None:
        """Haal data op van een Defender API endpoint.

        Ondersteunt automatische paginering via @odata.nextLink.

        Args:
            url: Volledige URL van het API endpoint.

        Returns:
            API response als dict, of None bij fouten.
        """
        all_values: list[dict] = []
        current_url: str | None = url

        async with aiohttp.ClientSession() as session:
            while current_url:
                headers = {
                    "Authorization": f"Bearer {self._get_token()}",
                    "Content-Type": "application/json",
                }

                async with session.get(current_url, headers=headers) as response:
                    if response.status != 200:
                        body = await response.text()
                        logger.error(
                            "Defender API fout %d voor %s: %s",
                            response.status,
                            current_url,
                            body[:500],
                        )
                        return None

                    data = await response.json()

                # Eerste request: als het geen list-achtig antwoord is, direct retourneren
                if not all_values and "value" not in data:
                    return data

                values = data.get("value", [])
                all_values.extend(values)

                # Paginering via @odata.nextLink
                current_url = data.get("@odata.nextLink")
                if current_url:
                    logger.debug(
                        "Paginering: %d records tot nu toe, volgende pagina...",
                        len(all_values),
                    )

        if all_values:
            return {"value": all_values}
        return None

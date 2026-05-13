"""Defender for Endpoint API client.

Gebruikt Managed Identity voor authenticatie tegen
https://api.securitycenter.microsoft.com.
"""

import asyncio
import logging

import aiohttp
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

DEFENDER_SCOPE = "https://api.securitycenter.microsoft.com/.default"
ADVANCED_HUNTING_URL = (
    "https://api.securitycenter.microsoft.com/api/advancedqueries/run"
)
MAX_RETRIES = 3
RETRY_BACKOFF_BASE = 2  # seconds


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
        Retry met exponential backoff bij throttling (429) en server errors (5xx).

        Args:
            url: Volledige URL van het API endpoint.

        Returns:
            API response als dict, of None bij fouten.
        """
        all_values: list[dict] = []
        current_url: str | None = url

        timeout = aiohttp.ClientTimeout(total=30, connect=5, sock_read=15)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            while current_url:
                data = await self._request_with_retry(session, current_url)
                if data is None:
                    return None

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

    async def run_advanced_query(self, kql: str) -> dict | None:
        """Voer een Advanced Hunting KQL query uit.

        Args:
            kql: KQL query string.

        Returns:
            Response dict met 'Results' key, of None bij fouten.
        """
        timeout = aiohttp.ClientTimeout(total=120, connect=5, sock_read=90)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            return await self._request_with_retry(
                session, ADVANCED_HUNTING_URL, method="POST", json_body={"Query": kql}
            )

    async def _request_with_retry(
        self,
        session: aiohttp.ClientSession,
        url: str,
        method: str = "GET",
        json_body: dict | None = None,
    ) -> dict | None:
        """Voer een HTTP request uit met retry en exponential backoff."""
        for attempt in range(MAX_RETRIES):
            headers = {
                "Authorization": f"Bearer {self._get_token()}",
                "Content-Type": "application/json",
            }

            try:
                if method == "POST":
                    ctx = session.post(url, headers=headers, json=json_body)
                else:
                    ctx = session.get(url, headers=headers)

                async with ctx as response:
                    if response.status == 200:
                        return await response.json()

                    if response.status == 429 or response.status >= 500:
                        retry_after = int(
                            response.headers.get(
                                "Retry-After", RETRY_BACKOFF_BASE ** (attempt + 1)
                            )
                        )
                        logger.warning(
                            "Defender API %d voor %s, retry %d/%d na %ds",
                            response.status,
                            url,
                            attempt + 1,
                            MAX_RETRIES,
                            retry_after,
                        )
                        await asyncio.sleep(retry_after)
                        continue

                    body = await response.text()
                    logger.error(
                        "Defender API fout %d voor %s: %s",
                        response.status,
                        url,
                        body[:500],
                    )
                    return None

            except aiohttp.ClientError as e:
                if attempt < MAX_RETRIES - 1:
                    wait = RETRY_BACKOFF_BASE ** (attempt + 1)
                    logger.warning(
                        "Defender API netwerk fout voor %s: %s, retry %d/%d na %ds",
                        url,
                        e,
                        attempt + 1,
                        MAX_RETRIES,
                        wait,
                    )
                    await asyncio.sleep(wait)
                else:
                    logger.error("Defender API definitief mislukt voor %s: %s", url, e)
                    return None

        logger.error(
            "Defender API max retries bereikt voor %s na %d pogingen",
            url,
            MAX_RETRIES,
        )
        return None

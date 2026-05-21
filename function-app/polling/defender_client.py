"""Defender for Endpoint API client.

Gebruikt Managed Identity voor authenticatie tegen
https://api.securitycenter.microsoft.com.
"""

from __future__ import annotations

import logging

import aiohttp
from azure.core.credentials import TokenCredential

from .http_base import BaseHttpClient

logger = logging.getLogger(__name__)

DEFENDER_SCOPE = "https://api.securitycenter.microsoft.com/.default"
ADVANCED_HUNTING_URL = (
    "https://api.securitycenter.microsoft.com/api/advancedqueries/run"
)


class DefenderClient(BaseHttpClient):
    """Client voor Microsoft Defender for Endpoint REST API."""

    api_label = "Defender"

    def __init__(self, credential: TokenCredential) -> None:
        super().__init__(credential, DEFENDER_SCOPE)

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
                session,
                ADVANCED_HUNTING_URL,
                method="POST",
                json_body={"Query": kql},
            )

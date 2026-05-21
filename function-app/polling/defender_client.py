"""Defender for Endpoint API client.

Uses Managed Identity to authenticate against
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
    """Client for the Microsoft Defender for Endpoint REST API."""

    api_label = "Defender"

    def __init__(self, credential: TokenCredential) -> None:
        super().__init__(credential, DEFENDER_SCOPE)

    async def run_advanced_query(self, kql: str) -> dict | None:
        """Run an Advanced Hunting KQL query.

        Args:
            kql: KQL query string.

        Returns:
            Response dict with 'Results' key, or None on error.
        """
        timeout = aiohttp.ClientTimeout(total=120, connect=5, sock_read=90)
        session = await self._session_for(timeout=timeout)
        return await self._request_with_retry(
            session,
            ADVANCED_HUNTING_URL,
            method="POST",
            json_body={"Query": kql},
        )

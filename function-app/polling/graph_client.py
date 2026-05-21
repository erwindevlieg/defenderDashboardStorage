"""Microsoft Graph API client.

Used for Secure Score, Intune and Alert data via
https://graph.microsoft.com.
"""

from __future__ import annotations

import logging

from azure.core.credentials import TokenCredential

from .http_base import BaseHttpClient

logger = logging.getLogger(__name__)

GRAPH_SCOPE = "https://graph.microsoft.com/.default"


class GraphClient(BaseHttpClient):
    """Client for the Microsoft Graph REST API."""

    api_label = "Graph"

    def __init__(self, credential: TokenCredential) -> None:
        super().__init__(credential, GRAPH_SCOPE)

    def _extra_headers(self) -> dict[str, str]:
        # Graph requires ConsistencyLevel for some advanced queries.
        return {"ConsistencyLevel": "eventual"}

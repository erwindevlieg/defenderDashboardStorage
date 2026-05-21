"""Token cache utilities.

Voorkomt dat per HTTP-request opnieuw een token wordt opgevraagd bij MSAL/IMDS.
Houdt tokens vast tot vlak voor expiratie (configureerbare marge).
"""

from __future__ import annotations

import logging
import os
import time
from threading import Lock
from typing import Protocol

logger = logging.getLogger(__name__)

# Marge in seconden vóór `expires_on` waarop we proactief verversen.
# Overschrijfbaar via env-var TOKEN_REFRESH_MARGIN_SECONDS.
DEFAULT_REFRESH_MARGIN_SECONDS = 300  # 5 minuten


def _default_margin() -> int:
    try:
        return int(os.environ.get("TOKEN_REFRESH_MARGIN_SECONDS", ""))
    except ValueError:
        return DEFAULT_REFRESH_MARGIN_SECONDS


class _TokenCredential(Protocol):
    """Subset van azure.core.credentials.TokenCredential die we hier gebruiken."""

    def get_token(self, *scopes: str) -> object:  # pragma: no cover - structural
        ...


class TokenCache:
    """Thread-safe cache voor één scope.

    Houdt het token + expiratie bij en haalt alleen een nieuw token op als
    het huidige token verlopen is (of bijna verloopt).
    """

    def __init__(
        self,
        credential: _TokenCredential,
        scope: str,
        refresh_margin_seconds: int | None = None,
    ) -> None:
        self._credential = credential
        self._scope = scope
        self._margin = (
            refresh_margin_seconds
            if refresh_margin_seconds is not None
            else _default_margin()
        )
        self._token: str | None = None
        self._expires_on: float = 0.0
        self._lock = Lock()

    def get(self) -> str:
        """Geef een geldig token terug, ververs indien nodig."""
        now = time.time()
        with self._lock:
            if self._token and now < (self._expires_on - self._margin):
                return self._token

            logger.debug("Token cache miss/refresh voor scope %s", self._scope)
            access_token = self._credential.get_token(self._scope)
            token: str = access_token.token  # type: ignore[attr-defined]
            self._token = token
            self._expires_on = float(access_token.expires_on)  # type: ignore[attr-defined]
            return token

    def invalidate(self) -> None:
        """Forceer een refresh bij de volgende `get()`."""
        with self._lock:
            self._token = None
            self._expires_on = 0.0

"""Token cache utilities.

Avoids requesting a new token from MSAL/IMDS on every HTTP request.
Holds tokens until just before expiry (configurable margin).
"""

from __future__ import annotations

import logging
import os
import time
from threading import Lock
from typing import Protocol

logger = logging.getLogger(__name__)

# Margin in seconds before ``expires_on`` at which we refresh proactively.
# Overridable via env-var TOKEN_REFRESH_MARGIN_SECONDS.
DEFAULT_REFRESH_MARGIN_SECONDS = 300  # 5 minutes


def _default_margin() -> int:
    try:
        return int(os.environ.get("TOKEN_REFRESH_MARGIN_SECONDS", ""))
    except ValueError:
        return DEFAULT_REFRESH_MARGIN_SECONDS


class _TokenCredential(Protocol):
    """Subset of azure.core.credentials.TokenCredential that we use here."""

    def get_token(self, *scopes: str) -> object:  # pragma: no cover - structural
        ...


class TokenCache:
    """Thread-safe cache for a single scope.

    Tracks token + expiry and only fetches a new token when the current one is
    expired (or about to expire).
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
        """Return a valid token, refresh if needed."""
        now = time.time()
        with self._lock:
            if self._token and now < (self._expires_on - self._margin):
                return self._token

            logger.debug("Token cache miss/refresh for scope %s", self._scope)
            access_token = self._credential.get_token(self._scope)
            token: str = access_token.token  # type: ignore[attr-defined]
            self._token = token
            self._expires_on = float(access_token.expires_on)  # type: ignore[attr-defined]
            return token

    def invalidate(self) -> None:
        """Force a refresh on the next ``get()``."""
        with self._lock:
            self._token = None
            self._expires_on = 0.0

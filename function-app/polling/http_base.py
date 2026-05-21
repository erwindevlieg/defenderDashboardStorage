"""Shared HTTP client layer for Defender + Graph.

Provides retry/backoff, pagination and Retry-After parsing so that
``DefenderClient`` and ``GraphClient`` only have to deal with API-specific
details.
"""

from __future__ import annotations

import asyncio
import logging
import random
from email.utils import parsedate_to_datetime
from typing import ClassVar

import aiohttp
from azure.core.credentials import TokenCredential

from .auth import TokenCache

logger = logging.getLogger(__name__)

MAX_RETRIES = 3
RETRY_BACKOFF_BASE = 2  # seconds
# PII protection: only log a short fragment of the error body.
ERROR_BODY_LOG_LIMIT = 200


def _backoff_with_jitter(attempt: int) -> float:
    """Exponential backoff with full-jitter (AWS-style)."""
    cap = RETRY_BACKOFF_BASE ** (attempt + 1)
    return random.uniform(0, cap)


def _parse_retry_after(header_value: str | None, attempt: int) -> float:
    """Parse a Retry-After header (seconds OR HTTP-date per RFC 7231).

    Never raises: on missing/unparseable value falls back to backoff+jitter.
    """
    if not header_value:
        return _backoff_with_jitter(attempt)
    # Seconds format
    try:
        seconds = float(header_value)
        # Clamp against negative/extreme values.
        return max(0.0, min(seconds, 300.0))
    except (TypeError, ValueError):
        pass
    # HTTP-date format
    try:
        dt = parsedate_to_datetime(header_value)
        import datetime as _dt

        now = _dt.datetime.now(tz=dt.tzinfo) if dt.tzinfo else _dt.datetime.utcnow()
        delta = (dt - now).total_seconds()
        return max(0.0, min(delta, 300.0))
    except (TypeError, ValueError):
        logger.debug("Unparseable Retry-After header: %r", header_value)
        return _backoff_with_jitter(attempt)


class BaseHttpClient:
    """Base client with token cache, retry/backoff and JSON pagination.

    Subclasses override ``_extra_headers()`` for API-specific headers and
    ``_timeout()`` for non-default timeouts.
    """

    api_label: ClassVar[str] = "HTTP"

    def __init__(self, credential: TokenCredential, scope: str) -> None:
        self._token_cache = TokenCache(credential, scope)
        self._session: aiohttp.ClientSession | None = None

    def _get_token(self) -> str:
        return self._token_cache.get()

    def _extra_headers(self) -> dict[str, str]:
        return {}

    def _timeout(self) -> aiohttp.ClientTimeout:
        return aiohttp.ClientTimeout(total=30, connect=5, sock_read=15)

    async def _session_for(
        self, timeout: aiohttp.ClientTimeout | None = None
    ) -> aiohttp.ClientSession:
        """Return a lazily-created shared session for this client.

        The session is kept alive for the lifetime of the engine run and closed
        via :meth:`aclose`. Reusing the connection pool avoids TLS handshakes
        per request.
        """
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(timeout=timeout or self._timeout())
        return self._session

    async def aclose(self) -> None:
        """Close the shared session if one was opened."""
        if self._session is not None and not self._session.closed:
            await self._session.close()
        self._session = None

    async def fetch(self, url: str) -> dict | list | None:
        """Fetch data with automatic pagination via ``@odata.nextLink``."""
        all_values: list[dict] = []
        current_url: str | None = url
        session = await self._session_for()

        while current_url:
            data = await self._request_with_retry(session, current_url)
            if data is None:
                return None

            if not all_values and "value" not in data:
                return data

            values = data.get("value", [])
            all_values.extend(values)

            current_url = data.get("@odata.nextLink")
            if current_url:
                logger.debug(
                    "%s pagination: %d records so far",
                    self.api_label,
                    len(all_values),
                )

        if all_values:
            return {"value": all_values}
        return None

    async def _request_with_retry(
        self,
        session: aiohttp.ClientSession,
        url: str,
        method: str = "GET",
        json_body: dict | None = None,
    ) -> dict | None:
        """Execute an HTTP request with retry, backoff+jitter and Retry-After."""
        for attempt in range(MAX_RETRIES):
            headers = {
                "Authorization": f"Bearer {self._get_token()}",
                "Content-Type": "application/json",
            }
            headers.update(self._extra_headers())

            try:
                if method == "POST":
                    ctx = session.post(url, headers=headers, json=json_body)
                else:
                    ctx = session.get(url, headers=headers)

                async with ctx as response:
                    if response.status == 200:
                        return await response.json()

                    if response.status == 429 or response.status >= 500:
                        retry_after = _parse_retry_after(
                            response.headers.get("Retry-After"), attempt
                        )
                        logger.warning(
                            "%s API %d for %s, retry %d/%d after %.1fs",
                            self.api_label,
                            response.status,
                            url,
                            attempt + 1,
                            MAX_RETRIES,
                            retry_after,
                        )
                        await asyncio.sleep(retry_after)
                        continue

                    # 4xx other than 429 → do not retry, log body truncated.
                    body = await response.text()
                    logger.error(
                        "%s API error %d for %s",
                        self.api_label,
                        response.status,
                        url,
                    )
                    logger.debug(
                        "%s API error body (truncated): %s",
                        self.api_label,
                        body[:ERROR_BODY_LOG_LIMIT],
                    )
                    return None

            except aiohttp.ClientError as e:
                if attempt < MAX_RETRIES - 1:
                    wait = _backoff_with_jitter(attempt)
                    logger.warning(
                        "%s API network error for %s: %s, retry %d/%d after %.1fs",
                        self.api_label,
                        url,
                        e,
                        attempt + 1,
                        MAX_RETRIES,
                        wait,
                    )
                    await asyncio.sleep(wait)
                else:
                    logger.error(
                        "%s API permanently failed for %s: %s",
                        self.api_label,
                        url,
                        e,
                    )
                    return None

        logger.error(
            "%s API max retries reached for %s after %d attempts",
            self.api_label,
            url,
            MAX_RETRIES,
        )
        return None

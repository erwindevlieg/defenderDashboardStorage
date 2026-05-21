"""Shared HTTP client layer for Defender + Graph.

Provides retry/backoff, pagination and Retry-After parsing so that
``DefenderClient`` and ``GraphClient`` only have to deal with API-specific
details.
"""

from __future__ import annotations

import asyncio
import logging
import os
import random
from collections.abc import AsyncIterator
from email.utils import parsedate_to_datetime
from typing import ClassVar

import aiohttp
from azure.core.credentials import TokenCredential

from .auth import TokenCache

logger = logging.getLogger(__name__)


class PaginationError(Exception):
    """Raised by ``iter_pages`` when a page fails mid-stream.

    Carries the last successful ``@odata.nextLink`` (i.e. the URL that *would*
    have produced the failed page) so the caller can persist a checkpoint and
    resume on the next run instead of restarting at page 1.
    """

    def __init__(self, url: str, last_next_link: str | None) -> None:
        super().__init__(f"pagination failed at {url}")
        self.url = url
        self.last_next_link = last_next_link


def _env_int(name: str, default: int, *, min_value: int = 0) -> int:
    """Read an int env var with a fallback and a lower bound."""
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        return max(min_value, int(raw))
    except ValueError:
        logger.warning("Invalid %s=%r, using default %d", name, raw, default)
        return default


MAX_RETRIES = _env_int("HTTP_MAX_RETRIES", 3, min_value=0)
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
        total = _env_int("HTTP_TOTAL_TIMEOUT_SECS", 30, min_value=1)
        connect = _env_int("HTTP_CONNECT_TIMEOUT_SECS", 5, min_value=1)
        read = _env_int("HTTP_READ_TIMEOUT_SECS", 15, min_value=1)
        return aiohttp.ClientTimeout(total=total, connect=connect, sock_read=read)

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

    async def iter_pages(
        self, url: str, start_next_link: str | None = None
    ) -> AsyncIterator[tuple[dict, str | None]]:
        """Yield API pages one at a time.

        Each yield is ``(page_dict, next_link)`` where ``next_link`` is the
        URL of the *next* page (or ``None`` for the last page).

        On failure raises :class:`PaginationError` whose ``last_next_link``
        attribute points at the URL that just failed. Callers should persist
        that value and pass it back as ``start_next_link`` on the next run to
        resume from that point.

        Args:
            url: Initial URL to fetch.
            start_next_link: Optional resume URL from a previous failed run.
                When provided, the initial ``url`` is ignored.
        """
        session = await self._session_for()
        current_url: str | None = start_next_link or url
        page_index = 0

        while current_url:
            data = await self._request_with_retry(session, current_url)
            if data is None:
                raise PaginationError(current_url, current_url)

            next_link = data.get("@odata.nextLink") if isinstance(data, dict) else None
            page_index += 1
            if next_link:
                logger.debug(
                    "%s pagination: yielded page %d (has next)",
                    self.api_label,
                    page_index,
                )
            yield data, next_link
            current_url = next_link

    async def fetch(
        self, url: str, start_next_link: str | None = None
    ) -> dict | list | None:
        """Fetch data with automatic pagination via ``@odata.nextLink``.

        Backwards-compatible wrapper around :meth:`iter_pages` that
        accumulates all pages and returns the merged dict. Prefer
        ``iter_pages`` for new code so failures do not throw away progress.
        """
        all_values: list[dict] = []
        first_non_value: dict | list | None = None

        try:
            async for page, _next in self.iter_pages(
                url, start_next_link=start_next_link
            ):
                if isinstance(page, dict) and "value" in page:
                    all_values.extend(page.get("value", []))
                elif not all_values and first_non_value is None:
                    first_non_value = page
        except PaginationError:
            return None

        if all_values:
            return {"value": all_values}
        return first_non_value

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

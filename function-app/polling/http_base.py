"""Gedeelde HTTP-clientlaag voor Defender + Graph.

Bevat retry/backoff, pagineringslogica en Retry-After parsing zodat
`DefenderClient` en `GraphClient` alleen API-specifieke details overhouden.
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
# PII-bescherming: alleen kort fragment van error body loggen.
ERROR_BODY_LOG_LIMIT = 200


def _backoff_with_jitter(attempt: int) -> float:
    """Exponential backoff met full-jitter (AWS-style)."""
    cap = RETRY_BACKOFF_BASE ** (attempt + 1)
    return random.uniform(0, cap)


def _parse_retry_after(header_value: str | None, attempt: int) -> float:
    """Parse Retry-After header (seconds OR HTTP-date per RFC 7231).

    Faalt nooit: bij ontbrekende/onparseerbare waarde valt terug op backoff+jitter.
    """
    if not header_value:
        return _backoff_with_jitter(attempt)
    # Seconds-formaat
    try:
        seconds = float(header_value)
        # Clamp tegen negatieve/extreme waardes.
        return max(0.0, min(seconds, 300.0))
    except (TypeError, ValueError):
        pass
    # HTTP-date-formaat
    try:
        dt = parsedate_to_datetime(header_value)
        import datetime as _dt

        now = _dt.datetime.now(tz=dt.tzinfo) if dt.tzinfo else _dt.datetime.utcnow()
        delta = (dt - now).total_seconds()
        return max(0.0, min(delta, 300.0))
    except (TypeError, ValueError):
        logger.debug("Onparseerbare Retry-After header: %r", header_value)
        return _backoff_with_jitter(attempt)


class BaseHttpClient:
    """Basisclient met token-cache, retry/backoff en JSON-paginering.

    Subklassen overschrijven `_extra_headers()` voor API-specifieke headers en
    `_timeout()` voor afwijkende timeouts.
    """

    api_label: ClassVar[str] = "HTTP"

    def __init__(self, credential: TokenCredential, scope: str) -> None:
        self._token_cache = TokenCache(credential, scope)

    def _get_token(self) -> str:
        return self._token_cache.get()

    def _extra_headers(self) -> dict[str, str]:
        return {}

    def _timeout(self) -> aiohttp.ClientTimeout:
        return aiohttp.ClientTimeout(total=30, connect=5, sock_read=15)

    async def fetch(self, url: str) -> dict | list | None:
        """Haal data op met automatische paginering via `@odata.nextLink`."""
        all_values: list[dict] = []
        current_url: str | None = url

        async with aiohttp.ClientSession(timeout=self._timeout()) as session:
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
                        "%s paginering: %d records tot nu toe",
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
        """Voer een HTTP-request uit met retry, backoff+jitter en Retry-After."""
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
                            "%s API %d voor %s, retry %d/%d na %.1fs",
                            self.api_label,
                            response.status,
                            url,
                            attempt + 1,
                            MAX_RETRIES,
                            retry_after,
                        )
                        await asyncio.sleep(retry_after)
                        continue

                    # 4xx anders dan 429 → niet retryen, beperkt body loggen.
                    body = await response.text()
                    logger.error(
                        "%s API fout %d voor %s",
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
                        "%s API netwerk fout voor %s: %s, retry %d/%d na %.1fs",
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
                        "%s API definitief mislukt voor %s: %s",
                        self.api_label,
                        url,
                        e,
                    )
                    return None

        logger.error(
            "%s API max retries bereikt voor %s na %d pogingen",
            self.api_label,
            url,
            MAX_RETRIES,
        )
        return None

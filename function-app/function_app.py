"""Defender Dashboard Storage — Azure Function App entry point."""

import asyncio
import json
import logging
import os
from functools import lru_cache

import azure.functions as func

from polling.engine import PollingEngine

logger = logging.getLogger(__name__)

app = func.FunctionApp()


@lru_cache(maxsize=1)
def _get_engine() -> PollingEngine:
    """Lazily construct the PollingEngine on first use.

    Keeps cold-start cost off paths that do not need it (e.g. ``health``).
    """
    return PollingEngine()


@app.timer_trigger(
    schedule="0 0 6 * * *",  # Daily at 06:00 UTC
    arg_name="timer",
    run_on_startup=False,
)
async def daily_poll(timer: func.TimerRequest) -> None:
    """Poll all daily endpoints (scores, recommendations, alerts)."""
    await _get_engine().run_daily()


@app.timer_trigger(
    schedule="0 0 8 * * 1",  # Weekly on Monday at 08:00 UTC
    arg_name="timer",
    run_on_startup=False,
)
async def weekly_poll(timer: func.TimerRequest) -> None:
    """Poll all weekly endpoints (device/software inventory, AV health, Intune)."""
    await _get_engine().run_weekly()


async def _check_dce() -> tuple[str, bool, str | None]:
    """Probe the Data Collection Endpoint with a HEAD request."""
    endpoint = os.environ.get("DCE_ENDPOINT", "")
    if not endpoint:
        return ("dce", False, "DCE_ENDPOINT not configured")
    try:
        import aiohttp

        timeout = aiohttp.ClientTimeout(total=5)
        async with (
            aiohttp.ClientSession(timeout=timeout) as session,
            session.head(endpoint, allow_redirects=False) as resp,
        ):
            # Any < 500 response indicates the endpoint is reachable;
            # 401/403/404 are acceptable here (auth/path not required).
            ok = resp.status < 500
            return ("dce", ok, None if ok else f"HTTP {resp.status}")
    except Exception as exc:  # noqa: BLE001
        return ("dce", False, str(exc))


async def _check_appconfig() -> tuple[str, bool, str | None]:
    """Verify App Configuration is reachable via a no-op list call."""
    endpoint = os.environ.get("APP_CONFIG_ENDPOINT", "")
    if not endpoint:
        return ("appconfig", False, "APP_CONFIG_ENDPOINT not configured")

    def _probe() -> None:
        engine = _get_engine()
        # Trigger a minimal listing; one item is enough.
        engine._load_endpoints("endpoints:daily")  # noqa: SLF001

    try:
        await asyncio.to_thread(_probe)
        return ("appconfig", True, None)
    except Exception as exc:  # noqa: BLE001
        return ("appconfig", False, str(exc))


async def _check_state_store() -> tuple[str, bool, str | None]:
    """Verify the failed-endpoint state table is reachable."""

    def _probe() -> str | None:
        store = _get_engine()._store  # noqa: SLF001
        if not store.enabled:
            return "state store disabled (no STATE_STORAGE_ACCOUNT)"
        # 0-second TTL means "load nothing, just query".
        store.load("daily", 0)
        return None

    try:
        err = await asyncio.to_thread(_probe)
        return ("state_store", err is None, err)
    except Exception as exc:  # noqa: BLE001
        return ("state_store", False, str(exc))


@app.function_name("health")
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint.

    Default: lightweight liveness probe (returns ``{"status": "ok"}``).
    ``?check=deep`` runs dependency probes (DCE, App Configuration, state
    store) in parallel and returns HTTP 503 on any failure.
    """
    if (req.params.get("check") or "").lower() != "deep":
        return func.HttpResponse('{"status": "ok"}', mimetype="application/json")

    results = await asyncio.gather(
        _check_dce(),
        _check_appconfig(),
        _check_state_store(),
    )
    checks = {name: {"ok": ok, "error": err} for name, ok, err in results}
    healthy = all(c["ok"] for c in checks.values())
    body = json.dumps({"status": "ok" if healthy else "degraded", "checks": checks})
    return func.HttpResponse(
        body,
        mimetype="application/json",
        status_code=200 if healthy else 503,
    )

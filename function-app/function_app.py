"""Defender Dashboard Storage — Azure Function App entry point."""

from functools import lru_cache

import azure.functions as func

from polling.engine import PollingEngine

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


@app.function_name("health")
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint."""
    return func.HttpResponse('{"status": "ok"}', mimetype="application/json")

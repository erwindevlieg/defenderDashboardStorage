"""Defender Dashboard Storage — Azure Function App entry point."""

import azure.functions as func

from polling.engine import PollingEngine

app = func.FunctionApp()
engine = PollingEngine()


@app.timer_trigger(
    schedule="0 0 6 * * *",  # Dagelijks om 06:00 UTC
    arg_name="timer",
    run_on_startup=False,
)
async def daily_poll(timer: func.TimerRequest) -> None:
    """Poll alle dagelijkse endpoints (scores, recommendations, alerts)."""
    await engine.run_daily()


@app.timer_trigger(
    schedule="0 0 8 * * 1",  # Wekelijks maandag om 08:00 UTC
    arg_name="timer",
    run_on_startup=False,
)
async def weekly_poll(timer: func.TimerRequest) -> None:
    """Poll alle wekelijkse endpoints (device/software inventory, AV health, Intune)."""
    await engine.run_weekly()


@app.function_name("health")
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint."""
    return func.HttpResponse('{"status": "ok"}', mimetype="application/json")

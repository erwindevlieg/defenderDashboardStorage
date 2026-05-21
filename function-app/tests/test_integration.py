"""Integration tests for the polling engine end-to-end flow."""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from polling.engine import PollingEngine


def _build_engine(mock_credential):
    """Build an engine with all clients replaced by async mocks."""
    with (
        patch("polling.engine.DefaultAzureCredential", return_value=mock_credential),
        patch(
            "polling.engine.AsyncDefaultAzureCredential",
            return_value=mock_credential,
        ),
    ):
        engine = PollingEngine()

    engine._ingestion = MagicMock()
    engine._ingestion.upload = AsyncMock()
    engine._ingestion.aclose = AsyncMock()
    engine._defender.aclose = AsyncMock()
    engine._graph.aclose = AsyncMock()
    return engine


class TestIntegration:
    @pytest.mark.asyncio
    async def test_daily_run_end_to_end(self, mock_credential):
        engine = _build_engine(mock_credential)

        engine._defender.fetch = AsyncMock(
            return_value={"value": [{"id": "alert-1", "severity": "High"}]}
        )
        engine._defender.run_advanced_query = AsyncMock(
            return_value={"Results": [{"RuleName": "AsrTest", "ActionType": "Blocked"}]}
        )
        engine._graph.fetch = AsyncMock(
            return_value={"value": [{"currentScore": 72.5}]}
        )

        await engine.run_daily()

        total_fetches = (
            engine._defender.fetch.call_count
            + engine._defender.run_advanced_query.call_count
            + engine._graph.fetch.call_count
        )
        assert total_fetches > 0
        assert engine._ingestion.upload.await_count == total_fetches

    @pytest.mark.asyncio
    async def test_endpoint_failure_continues(self, mock_credential):
        engine = _build_engine(mock_credential)

        call_count = {"n": 0}

        async def defender_side_effect(url):
            call_count["n"] += 1
            if call_count["n"] == 1:
                return None
            return {"value": [{"id": "device-1"}]}

        engine._defender.fetch = AsyncMock(side_effect=defender_side_effect)
        engine._defender.run_advanced_query = AsyncMock(
            return_value={"Results": [{"RuleName": "AsrTest"}]}
        )
        engine._graph.fetch = AsyncMock(
            return_value={"value": [{"currentScore": 72.5}]}
        )

        await engine.run_daily()

        assert engine._ingestion.upload.await_count >= 1

    @pytest.mark.asyncio
    async def test_no_data_skips_upload(self, mock_credential):
        engine = _build_engine(mock_credential)

        engine._defender.fetch = AsyncMock(return_value=None)
        engine._defender.run_advanced_query = AsyncMock(return_value=None)
        engine._graph.fetch = AsyncMock(return_value=None)

        await engine.run_daily()

        engine._ingestion.upload.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_parallel_polling_respects_semaphore(
        self, mock_credential, monkeypatch
    ):
        """Semaphore must cap simultaneous endpoint processing at POLL_CONCURRENCY."""
        monkeypatch.setenv("POLL_CONCURRENCY", "3")
        engine = _build_engine(mock_credential)

        # Force a fixed endpoint list so we control the count.
        endpoints = [
            {
                "key": f"ep-{i}",
                "url": "https://graph.microsoft.com/v1.0/x",
                "scope": "https://graph.microsoft.com/.default",
                "stream": f"Custom-Test{i}_CL",
                "dcr": "daily",
                "transform": "graphList",
            }
            for i in range(10)
        ]
        engine._load_endpoints = MagicMock(return_value=endpoints)
        engine._load_failed = MagicMock(return_value=[])
        engine._save_failed = MagicMock()
        monkeypatch.setenv("DCR_DAILY_SCORES_ID", "dcr-test")

        in_flight = {"current": 0, "peak": 0}

        async def fetch_side_effect(url):
            in_flight["current"] += 1
            in_flight["peak"] = max(in_flight["peak"], in_flight["current"])
            await asyncio.sleep(0.01)
            in_flight["current"] -= 1
            return {"value": [{"x": 1}]}

        engine._graph.fetch = AsyncMock(side_effect=fetch_side_effect)

        await engine.run_daily()

        assert in_flight["peak"] <= 3, f"semaphore breached: peak={in_flight['peak']}"
        assert engine._ingestion.upload.await_count == 10

    @pytest.mark.asyncio
    async def test_failed_endpoint_returned_for_retry(
        self, mock_credential, monkeypatch
    ):
        """Endpoints that raise must be returned in the failed list."""
        engine = _build_engine(mock_credential)
        monkeypatch.setenv("DCR_DAILY_SCORES_ID", "dcr-test")

        endpoints = [
            {
                "key": "good",
                "url": "https://graph.microsoft.com/v1.0/x",
                "scope": "https://graph.microsoft.com/.default",
                "stream": "Custom-Good_CL",
                "dcr": "daily",
                "transform": "graphList",
            },
            {
                "key": "bad",
                "url": "https://graph.microsoft.com/v1.0/y",
                "scope": "https://graph.microsoft.com/.default",
                "stream": "Custom-Bad_CL",
                "dcr": "daily",
                "transform": "graphList",
            },
        ]
        engine._load_endpoints = MagicMock(return_value=endpoints)
        engine._load_failed = MagicMock(return_value=[])
        captured: dict[str, list] = {}

        def fake_save(schedule, failed):
            captured["failed"] = failed

        engine._save_failed = fake_save

        async def fetch_side_effect(url):
            if "y" in url:
                raise RuntimeError("boom")
            return {"value": [{"x": 1}]}

        engine._graph.fetch = AsyncMock(side_effect=fetch_side_effect)

        await engine.run_daily()

        assert len(captured["failed"]) == 1
        assert captured["failed"][0]["key"] == "bad"

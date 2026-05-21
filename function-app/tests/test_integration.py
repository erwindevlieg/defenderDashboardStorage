"""Integration tests for the polling engine end-to-end flow."""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from polling.engine import PollingEngine
from polling.http_base import PaginationError


def _bridge_iter_pages(client):
    """Make ``iter_pages`` delegate to the mocked ``fetch`` for the same client.

    Tests historically mock ``client.fetch``; the engine now calls
    ``client.iter_pages`` for list-transform endpoints. To keep those tests
    expressive, we route ``iter_pages`` back through ``fetch`` so a single
    mock keeps controlling both paths. ``fetch`` returning ``None`` is
    translated into :class:`PaginationError` so the engine takes its failure
    branch (matching production semantics).
    """

    async def _iter(url, start_next_link=None):
        target = start_next_link or url
        try:
            data = await client.fetch(target)
        except Exception:
            raise
        if data is None:
            raise PaginationError(target, target)
        if isinstance(data, dict):
            yield data, None
        else:
            yield {"value": data}, None

    client.iter_pages = _iter


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
    _bridge_iter_pages(engine._defender)
    _bridge_iter_pages(engine._graph)
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
        ep, attempts = captured["failed"][0]
        assert ep["key"] == "bad"
        assert attempts == 1

    @pytest.mark.asyncio
    async def test_pagination_failure_persists_resume_checkpoint(
        self, mock_credential, monkeypatch
    ):
        """Mid-stream pagination failure must upload prior pages and stash resume link."""
        engine = _build_engine(mock_credential)
        monkeypatch.setenv("DCR_DAILY_SCORES_ID", "dcr-test")

        endpoints = [
            {
                "key": "paged",
                "url": "https://graph.microsoft.com/v1.0/page1",
                "scope": "https://graph.microsoft.com/.default",
                "stream": "Custom-Paged_CL",
                "dcr": "daily",
                "transform": "graphList",
            }
        ]
        engine._load_endpoints = MagicMock(return_value=endpoints)
        engine._load_failed = MagicMock(return_value=[])
        captured: dict[str, list] = {}
        engine._save_failed = lambda schedule, failed: captured.setdefault(
            "failed", failed
        )

        async def iter_pages_side_effect(url, start_next_link=None):
            # Yield two pages successfully, fail when the caller asks for the third.
            yield {"value": [{"x": 1}], "@odata.nextLink": "next-2"}, "next-2"
            yield {"value": [{"x": 2}], "@odata.nextLink": "next-3"}, "next-3"
            raise PaginationError("next-3", "next-3")

        engine._graph.iter_pages = iter_pages_side_effect

        await engine.run_daily()

        # Two pages were uploaded before the failure.
        assert engine._ingestion.upload.await_count == 2
        # Endpoint is queued for retry with the resume checkpoint set.
        assert len(captured["failed"]) == 1
        ep, attempts = captured["failed"][0]
        assert ep["key"] == "paged"
        assert ep["resume_next_link"] == "next-3"
        assert attempts == 1

    @pytest.mark.asyncio
    async def test_resume_uses_stored_next_link(self, mock_credential, monkeypatch):
        """A retried endpoint with ``resume_next_link`` must resume there, not from page 1."""
        engine = _build_engine(mock_credential)
        monkeypatch.setenv("DCR_DAILY_SCORES_ID", "dcr-test")

        endpoints = [
            {
                "key": "paged",
                "url": "https://graph.microsoft.com/v1.0/page1",
                "scope": "https://graph.microsoft.com/.default",
                "stream": "Custom-Paged_CL",
                "dcr": "daily",
                "transform": "graphList",
                "resume_next_link": "https://graph.microsoft.com/v1.0/page3",
            }
        ]
        engine._load_endpoints = MagicMock(return_value=endpoints)
        engine._load_failed = MagicMock(return_value=[])
        captured: dict[str, list] = {}
        engine._save_failed = lambda schedule, failed: captured.setdefault(
            "failed", failed
        )

        seen_urls: list[str] = []

        async def iter_pages_side_effect(url, start_next_link=None):
            seen_urls.append(start_next_link or url)
            yield {"value": [{"x": 3}]}, None

        engine._graph.iter_pages = iter_pages_side_effect

        await engine.run_daily()

        # Resume URL was used, not the original page1.
        assert seen_urls == ["https://graph.microsoft.com/v1.0/page3"]
        # Successful drain → endpoint is not in the failed list, checkpoint cleared.
        assert captured.get("failed", []) == []
        assert "resume_next_link" not in endpoints[0]

    @pytest.mark.asyncio
    async def test_endpoint_poisons_after_threshold(self, mock_credential, monkeypatch):
        """After ``MAX_POISON_ATTEMPTS`` failures the endpoint is poisoned."""
        monkeypatch.setenv("MAX_POISON_ATTEMPTS", "3")
        engine = _build_engine(mock_credential)
        monkeypatch.setenv("DCR_DAILY_SCORES_ID", "dcr-test")

        bad_ep = {
            "key": "broken",
            "url": "https://graph.microsoft.com/v1.0/x",
            "scope": "https://graph.microsoft.com/.default",
            "stream": "Custom-Broken_CL",
            "dcr": "daily",
            "transform": "graphList",
        }
        engine._load_endpoints = MagicMock(return_value=[])
        # Simulate this endpoint has already failed twice on previous runs.
        engine._load_failed = MagicMock(return_value=[(0.0, bad_ep, 2)])

        captured: dict[str, list] = {"failed": [], "poison": []}
        engine._save_failed = lambda schedule, failed: captured.update(failed=failed)
        engine._save_poisoned = lambda schedule, ep, attempts: captured[
            "poison"
        ].append((ep, attempts))

        async def iter_pages_side_effect(url, start_next_link=None):
            raise PaginationError(url, url)
            yield  # pragma: no cover  # make this an async generator

        engine._graph.iter_pages = iter_pages_side_effect

        await engine.run_daily()

        # Third failure → poisoned, not requeued.
        assert captured["failed"] == []
        assert len(captured["poison"]) == 1
        ep, attempts = captured["poison"][0]
        assert ep["key"] == "broken"
        assert attempts == 3

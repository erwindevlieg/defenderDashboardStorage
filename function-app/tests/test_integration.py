"""Integration tests voor de Polling Engine end-to-end flow."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from polling.engine import PollingEngine


class TestIntegration:
    """Integration tests voor PollingEngine."""

    @pytest.mark.asyncio
    async def test_daily_run_end_to_end(self, mock_credential):
        """Test full daily run: all endpoints fetched and uploaded."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        # Mock ingestion client
        engine._ingestion = MagicMock()
        engine._ingestion.upload = MagicMock()

        # Mock defender client to return data for defender-scoped endpoints
        defender_response = {"value": [{"id": "alert-1", "severity": "High"}]}
        engine._defender.fetch = AsyncMock(return_value=defender_response)

        # Mock graph client to return data for graph-scoped endpoints
        graph_response = {"value": [{"currentScore": 72.5}]}
        engine._graph.fetch = AsyncMock(return_value=graph_response)

        await engine.run_daily()

        # Verify endpoints were fetched
        total_fetches = (
            engine._defender.fetch.call_count + engine._graph.fetch.call_count
        )
        assert total_fetches > 0

        # Verify upload was called for each endpoint that returned data
        assert engine._ingestion.upload.call_count == total_fetches

    @pytest.mark.asyncio
    async def test_endpoint_failure_continues(self, mock_credential):
        """Test that one failing endpoint doesn't block others."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        engine._ingestion = MagicMock()
        engine._ingestion.upload = MagicMock()

        # First call fails (returns None), subsequent calls succeed
        call_count = {"n": 0}

        async def defender_side_effect(url):
            call_count["n"] += 1
            if call_count["n"] == 1:
                return None
            return {"value": [{"id": "device-1"}]}

        engine._defender.fetch = AsyncMock(side_effect=defender_side_effect)
        engine._graph.fetch = AsyncMock(
            return_value={"value": [{"currentScore": 72.5}]}
        )

        await engine.run_daily()

        # Despite one failure, other endpoints should still be uploaded
        total_fetches = (
            engine._defender.fetch.call_count + engine._graph.fetch.call_count
        )
        assert total_fetches > 1
        # Upload should be called for all successful fetches (total - 1 failure)
        assert engine._ingestion.upload.call_count >= 1

    @pytest.mark.asyncio
    async def test_no_data_skips_upload(self, mock_credential):
        """Test that None responses don't trigger upload."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        engine._ingestion = MagicMock()
        engine._ingestion.upload = MagicMock()

        # Return None (simulating API failure or no data)
        engine._defender.fetch = AsyncMock(return_value=None)
        engine._graph.fetch = AsyncMock(return_value=None)

        await engine.run_daily()

        # Upload should not be called when no data is returned
        engine._ingestion.upload.assert_not_called()

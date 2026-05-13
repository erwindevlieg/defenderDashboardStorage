"""Tests voor de Defender API client."""

from unittest.mock import AsyncMock, MagicMock, patch

import aiohttp
import pytest

from polling.defender_client import DefenderClient, DEFENDER_SCOPE


class TestDefenderClient:
    """Tests voor DefenderClient."""

    def test_token_scope(self, mock_credential):
        """Test dat de juiste scope wordt gebruikt voor token acquisitie."""
        client = DefenderClient(mock_credential)
        token = client._get_token()

        mock_credential.get_token.assert_called_with(DEFENDER_SCOPE)
        assert token == "test-token-123"

    @pytest.mark.asyncio
    async def test_fetch_single_object(self, mock_credential, sample_exposure_score):
        """Test ophalen van een enkel object (bijv. Exposure Score)."""
        client = DefenderClient(mock_credential)

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value=sample_exposure_score)

        mock_session = AsyncMock()
        mock_session.get = MagicMock(
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_response),
                __aexit__=AsyncMock(return_value=False),
            )
        )

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ):
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        assert result is not None
        assert result["score"] == 33.49

    @pytest.mark.asyncio
    async def test_fetch_list_response(self, mock_credential, sample_device_list):
        """Test ophalen van een lijst met paginering."""
        client = DefenderClient(mock_credential)

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value=sample_device_list)

        mock_session = AsyncMock()
        mock_session.get = MagicMock(
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_response),
                __aexit__=AsyncMock(return_value=False),
            )
        )

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ):
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/machines"
            )

        assert result is not None
        assert len(result["value"]) == 2


class TestDefenderClientRetry:
    """Tests voor DefenderClient retry logic."""

    def _make_response(self, status, json_data=None, headers=None):
        """Helper to create a mock response."""
        resp = AsyncMock()
        resp.status = status
        resp.headers = headers or {}
        resp.json = AsyncMock(return_value=json_data or {})
        resp.text = AsyncMock(return_value="error body")
        return resp

    def _session_with_responses(self, responses):
        """Create a mock session that returns responses in sequence."""
        call_count = {"n": 0}

        def side_effect(*args, **kwargs):
            idx = call_count["n"]
            call_count["n"] += 1
            resp = responses[idx]
            return AsyncMock(
                __aenter__=AsyncMock(return_value=resp),
                __aexit__=AsyncMock(return_value=False),
            )

        mock_session = AsyncMock()
        mock_session.get = MagicMock(side_effect=side_effect)
        return mock_session

    @pytest.mark.asyncio
    async def test_retry_on_429_throttling(self, mock_credential, sample_exposure_score):
        """Test that 429 triggers retry and eventual success."""
        client = DefenderClient(mock_credential)

        responses = [
            self._make_response(429, headers={"Retry-After": "1"}),
            self._make_response(200, json_data=sample_exposure_score),
        ]
        mock_session = self._session_with_responses(responses)

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ), patch("asyncio.sleep", new_callable=AsyncMock) as mock_sleep:
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        assert result is not None
        assert result["score"] == 33.49
        assert mock_session.get.call_count == 2
        mock_sleep.assert_called()

    @pytest.mark.asyncio
    async def test_retry_on_500_server_error(
        self, mock_credential, sample_exposure_score
    ):
        """Test that 500 triggers retry and eventual success."""
        client = DefenderClient(mock_credential)

        responses = [
            self._make_response(500),
            self._make_response(200, json_data=sample_exposure_score),
        ]
        mock_session = self._session_with_responses(responses)

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ), patch("asyncio.sleep", new_callable=AsyncMock):
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        assert result is not None
        assert result["score"] == 33.49
        assert mock_session.get.call_count == 2

    @pytest.mark.asyncio
    async def test_retry_respects_retry_after_header(self, mock_credential):
        """Test that Retry-After header value is used for sleep duration."""
        client = DefenderClient(mock_credential)

        responses = [
            self._make_response(429, headers={"Retry-After": "7"}),
            self._make_response(200, json_data={"score": 1.0}),
        ]
        mock_session = self._session_with_responses(responses)

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ), patch("asyncio.sleep", new_callable=AsyncMock) as mock_sleep:
            await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        mock_sleep.assert_called_with(7)

    @pytest.mark.asyncio
    async def test_max_retries_exceeded(self, mock_credential):
        """Test that None is returned after MAX_RETRIES failures."""
        client = DefenderClient(mock_credential)

        responses = [
            self._make_response(500),
            self._make_response(500),
            self._make_response(500),
        ]
        mock_session = self._session_with_responses(responses)

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ), patch("asyncio.sleep", new_callable=AsyncMock):
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        assert result is None
        assert mock_session.get.call_count == 3

    @pytest.mark.asyncio
    async def test_no_retry_on_400(self, mock_credential):
        """Test that 400 returns None immediately without retry."""
        client = DefenderClient(mock_credential)

        responses = [self._make_response(400)]
        mock_session = self._session_with_responses(responses)

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ), patch("asyncio.sleep", new_callable=AsyncMock) as mock_sleep:
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        assert result is None
        assert mock_session.get.call_count == 1
        mock_sleep.assert_not_called()

    @pytest.mark.asyncio
    async def test_retry_on_network_error(
        self, mock_credential, sample_exposure_score
    ):
        """Test that aiohttp.ClientError triggers retry."""
        client = DefenderClient(mock_credential)

        success_resp = self._make_response(200, json_data=sample_exposure_score)

        call_count = {"n": 0}

        def side_effect(*args, **kwargs):
            idx = call_count["n"]
            call_count["n"] += 1
            if idx == 0:
                raise aiohttp.ClientError("Connection reset")
            return AsyncMock(
                __aenter__=AsyncMock(return_value=success_resp),
                __aexit__=AsyncMock(return_value=False),
            )

        mock_session = AsyncMock()
        mock_session.get = MagicMock(side_effect=side_effect)

        with patch(
            "aiohttp.ClientSession",
            return_value=AsyncMock(
                __aenter__=AsyncMock(return_value=mock_session),
                __aexit__=AsyncMock(return_value=False),
            ),
        ), patch("asyncio.sleep", new_callable=AsyncMock):
            result = await client.fetch(
                "https://api.securitycenter.microsoft.com/api/exposureScore"
            )

        assert result is not None
        assert result["score"] == 33.49
        assert mock_session.get.call_count == 2

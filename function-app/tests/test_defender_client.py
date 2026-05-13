"""Tests voor de Defender API client."""

from unittest.mock import AsyncMock, MagicMock, patch

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
        mock_session.get = MagicMock(return_value=AsyncMock(
            __aenter__=AsyncMock(return_value=mock_response),
            __aexit__=AsyncMock(return_value=False),
        ))

        with patch("aiohttp.ClientSession", return_value=AsyncMock(
            __aenter__=AsyncMock(return_value=mock_session),
            __aexit__=AsyncMock(return_value=False),
        )):
            result = await client.fetch("https://api.securitycenter.microsoft.com/api/exposureScore")

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
        mock_session.get = MagicMock(return_value=AsyncMock(
            __aenter__=AsyncMock(return_value=mock_response),
            __aexit__=AsyncMock(return_value=False),
        ))

        with patch("aiohttp.ClientSession", return_value=AsyncMock(
            __aenter__=AsyncMock(return_value=mock_session),
            __aexit__=AsyncMock(return_value=False),
        )):
            result = await client.fetch("https://api.securitycenter.microsoft.com/api/machines")

        assert result is not None
        assert len(result["value"]) == 2

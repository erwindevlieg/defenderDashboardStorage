"""Tests voor de Graph API client."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from polling.graph_client import GraphClient, GRAPH_SCOPE


class TestGraphClient:
    """Tests voor GraphClient."""

    def test_token_scope(self, mock_credential):
        """Test dat de juiste scope wordt gebruikt."""
        client = GraphClient(mock_credential)
        token = client._get_token()

        mock_credential.get_token.assert_called_with(GRAPH_SCOPE)
        assert token == "test-token-123"

    @pytest.mark.asyncio
    async def test_fetch_secure_scores(
        self, mock_credential, sample_graph_secure_scores
    ):
        """Test ophalen van Secure Scores."""
        client = GraphClient(mock_credential)

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value=sample_graph_secure_scores)

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
                "https://graph.microsoft.com/v1.0/security/secureScores?$top=1"
            )

        assert result is not None
        assert result["value"][0]["currentScore"] == 72.5

"""Tests voor de Polling Engine."""

from unittest.mock import patch


from polling.engine import PollingEngine


class TestPollingEngine:
    """Tests voor PollingEngine."""

    def test_transform_single(self, mock_credential):
        """Test transformatie van een enkel object."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform({"score": 33.49}, "single")
        assert result == [{"score": 33.49}]

    def test_transform_single_none(self, mock_credential):
        """Test transformatie van None."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform(None, "single")
        assert result == []

    def test_transform_list(self, mock_credential, sample_device_list):
        """Test transformatie van een list response."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform(sample_device_list, "list")
        assert len(result) == 2
        assert result[0]["id"] == "device-1"

    def test_transform_graph_list(self, mock_credential, sample_graph_secure_scores):
        """Test transformatie van een Graph list response."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform(sample_graph_secure_scores, "graphList")
        assert len(result) == 1
        assert result[0]["currentScore"] == 72.5

    def test_transform_empty_value(self, mock_credential):
        """Test transformatie van lege value array."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform({"value": []}, "list")
        assert result == []

    def test_load_fallback_endpoints(self, mock_credential):
        """Test fallback endpoint loading uit JSON."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        daily = engine._load_fallback_endpoints("endpoints:daily")
        assert len(daily) > 0
        assert all("url" in ep for ep in daily)

    def test_load_fallback_weekly(self, mock_credential):
        """Test fallback endpoint loading voor wekelijks."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        weekly = engine._load_fallback_endpoints("endpoints:weekly")
        assert len(weekly) > 0
        assert any("intune" in ep.get("key", "").lower() for ep in weekly)

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

    def test_transform_advanced_hunting(self, mock_credential):
        """Test transformatie van Advanced Hunting response."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        ah_response = {
            "Schema": [{"Name": "RuleName", "Type": "String"}],
            "Results": [
                {"RuleName": "AsrLsassCredentialTheft", "ActionType": "Blocked"},
                {"RuleName": "AsrOfficeCommInjection", "ActionType": "Audited"},
            ],
        }
        result = engine._transform(ah_response, "advancedHunting")
        assert len(result) == 2
        assert result[0]["RuleName"] == "AsrLsassCredentialTheft"

    def test_transform_advanced_hunting_empty(self, mock_credential):
        """Test transformatie van lege AH response."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform({"Results": []}, "advancedHunting")
        assert result == []

    def test_transform_advanced_hunting_none(self, mock_credential):
        """Test transformatie van None AH response."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        result = engine._transform(None, "advancedHunting")
        assert result == []

    def test_fallback_endpoints_have_ah_queries(self, mock_credential):
        """Test dat AH endpoints een query veld bevatten."""
        with patch(
            "polling.engine.DefaultAzureCredential", return_value=mock_credential
        ):
            engine = PollingEngine()

        daily = engine._load_fallback_endpoints("endpoints:daily")
        ah_endpoints = [ep for ep in daily if ep.get("transform") == "advancedHunting"]
        assert (
            len(ah_endpoints) >= 4
        )  # asrEvents, protectionState, avOutdated, avDetections
        assert all("query" in ep and ep["query"] for ep in ah_endpoints)

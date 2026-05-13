"""Shared test fixtures."""

import os
from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture(autouse=True)
def mock_env():
    """Stel environment variables in voor tests."""
    env_vars = {
        "AZURE_CLIENT_ID": "test-client-id",
        "DCE_ENDPOINT": "https://test-dce.westeurope.ingest.monitor.azure.com",
        "DCR_DAILY_SCORES_ID": "dcr-daily-test-id",
        "DCR_WEEKLY_SNAPSHOTS_ID": "dcr-weekly-test-id",
        "DCR_INTUNE_ID": "dcr-intune-test-id",
        "APP_CONFIG_ENDPOINT": "",
    }
    with patch.dict(os.environ, env_vars):
        yield


@pytest.fixture
def mock_credential():
    """Mock Azure credential."""
    credential = MagicMock()
    credential.get_token.return_value = MagicMock(token="test-token-123")
    return credential


@pytest.fixture
def sample_exposure_score():
    """Voorbeeld Exposure Score API response."""
    return {"score": 33.49, "rbacGroupName": None}


@pytest.fixture
def sample_device_list():
    """Voorbeeld Device Inventory API response."""
    return {
        "value": [
            {
                "id": "device-1",
                "computerDnsName": "workstation-01",
                "osPlatform": "Windows10",
                "riskScore": "Medium",
                "exposureLevel": "Low",
                "healthStatus": "Active",
            },
            {
                "id": "device-2",
                "computerDnsName": "workstation-02",
                "osPlatform": "Windows11",
                "riskScore": "Low",
                "exposureLevel": "Low",
                "healthStatus": "Active",
            },
        ]
    }


@pytest.fixture
def sample_graph_secure_scores():
    """Voorbeeld Graph Secure Score API response."""
    return {
        "value": [
            {
                "currentScore": 72.5,
                "maxScore": 100.0,
                "averageComparativeScores": [
                    {"basis": "AllTenants", "averageScore": 55.0}
                ],
            }
        ]
    }

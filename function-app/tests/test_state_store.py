"""Tests voor FailedEndpointStore (best-effort persistence)."""

import json
import time
from unittest.mock import MagicMock, patch

from polling.state_store import FailedEndpointStore


class TestDisabledStore:
    """Zonder STATE_STORAGE_ACCOUNT moet de store soepel uitgeschakeld zijn."""

    def test_disabled_when_account_empty(self, mock_credential):
        store = FailedEndpointStore(mock_credential, account_name="")
        assert not store.enabled
        # Operaties moeten no-op zijn zonder crash.
        assert store.load("daily", ttl_seconds=3600) == []
        store.save("daily", [{"key": "x"}])
        store.clear("daily")


class TestEnabledStore:
    """Met een gemockte TableClient: round-trip + TTL-filter."""

    def _make_store(self, mock_credential, entities):
        fake_client = MagicMock()
        fake_client.query_entities.return_value = entities
        with patch("polling.state_store._build_table_client", return_value=fake_client):
            store = FailedEndpointStore(mock_credential, account_name="stteststore")
        return store, fake_client

    def test_load_filters_expired_and_returns_fresh(self, mock_credential):
        now = time.time()
        entities = [
            {
                "PartitionKey": "daily",
                "RowKey": "fresh",
                "QueuedAt": now - 60,
                "AttemptCount": 2,
                "Endpoint": json.dumps({"key": "ep-fresh"}),
            },
            {
                "PartitionKey": "daily",
                "RowKey": "stale",
                "QueuedAt": now - 99_999,
                "AttemptCount": 1,
                "Endpoint": json.dumps({"key": "ep-stale"}),
            },
        ]
        store, client = self._make_store(mock_credential, entities)

        result = store.load("daily", ttl_seconds=3600)

        assert len(result) == 1
        ts, ep, attempts = result[0]
        assert ep["key"] == "ep-fresh"
        assert attempts == 2
        # Verlopen entry moet verwijderd worden.
        client.delete_entity.assert_called_once_with(
            partition_key="daily", row_key="stale"
        )

    def test_load_defaults_missing_attempt_count_to_zero(self, mock_credential):
        now = time.time()
        entities = [
            {
                "PartitionKey": "daily",
                "RowKey": "legacy",
                "QueuedAt": now - 30,
                "Endpoint": json.dumps({"key": "ep-legacy"}),
            }
        ]
        store, _client = self._make_store(mock_credential, entities)

        result = store.load("daily", ttl_seconds=3600)
        assert len(result) == 1
        assert result[0][2] == 0

    def test_save_clears_then_inserts(self, mock_credential):
        store, client = self._make_store(mock_credential, [])
        store.save("weekly", [({"key": "a"}, 1), ({"key": "b"}, 3)])
        assert client.create_entity.call_count == 2
        # AttemptCount is written into each entity.
        written = [call.args[0] for call in client.create_entity.call_args_list]
        assert {e["AttemptCount"] for e in written} == {1, 3}

    def test_save_accepts_plain_dicts_legacy(self, mock_credential):
        store, client = self._make_store(mock_credential, [])
        store.save("daily", [{"key": "x"}])
        assert client.create_entity.call_count == 1
        assert client.create_entity.call_args.args[0]["AttemptCount"] == 1

    def test_save_poisoned_writes_to_poison_partition(self, mock_credential):
        store, client = self._make_store(mock_credential, [])
        store.save_poisoned("daily", {"key": "broken"}, attempt_count=5)
        assert client.create_entity.call_count == 1
        entity = client.create_entity.call_args.args[0]
        assert entity["PartitionKey"] == "poison-daily"
        assert entity["AttemptCount"] == 5

    def test_load_handles_query_failure_gracefully(self, mock_credential):
        store, client = self._make_store(mock_credential, [])
        client.query_entities.side_effect = RuntimeError("transient")
        assert store.load("daily", ttl_seconds=3600) == []

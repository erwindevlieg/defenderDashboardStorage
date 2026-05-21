"""Tests for IngestionClient schema validation."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from polling.ingestion import IngestionClient, SchemaValidationError, _validate_records


class TestValidateRecords:
    def test_no_expected_columns_is_passthrough(self):
        records = [{"a": 1, "b": 2}]
        out = _validate_records(records, None, "S", strict=False)
        assert out == records

    def test_filters_unexpected_columns_lenient(self):
        records = [{"a": 1, "extra": 2}, {"a": 3, "extra": 4}]
        out = _validate_records(records, ["a"], "S", strict=False)
        assert out == [{"a": 1}, {"a": 3}]

    def test_strict_raises_on_mismatch(self):
        records = [{"a": 1, "extra": 2}]
        with pytest.raises(SchemaValidationError):
            _validate_records(records, ["a"], "S", strict=True)

    def test_records_matching_schema_pass_through(self):
        records = [{"a": 1, "b": 2}]
        out = _validate_records(records, ["a", "b"], "S", strict=False)
        assert out == records


def _make_sdk_mock():
    sdk = MagicMock()
    sdk.upload = AsyncMock()
    sdk.close = AsyncMock()
    return sdk


class TestIngestionClient:
    @pytest.mark.asyncio
    async def test_upload_filters_records_lenient(self, mock_credential):
        with patch("polling.ingestion.AzureLogsIngestionClient") as MockSdk:
            sdk = _make_sdk_mock()
            MockSdk.return_value = sdk
            client = IngestionClient(mock_credential)

            await client.upload(
                dcr_id="dcr-123",
                stream_name="Custom-Test_CL",
                records=[{"a": 1, "extra": 2}],
                expected_columns=["a"],
            )

            sdk.upload.assert_awaited_once()
            kwargs = sdk.upload.call_args.kwargs
            assert kwargs["logs"] == [{"a": 1}]

    @pytest.mark.asyncio
    async def test_upload_skips_when_all_filtered_out(self, mock_credential):
        with patch("polling.ingestion.AzureLogsIngestionClient") as MockSdk:
            sdk = _make_sdk_mock()
            MockSdk.return_value = sdk
            client = IngestionClient(mock_credential)

            await client.upload(
                dcr_id="dcr-123",
                stream_name="Custom-Test_CL",
                records=[{"only_unexpected": 1}],
                expected_columns=["a"],
            )

            sdk.upload.assert_not_called()

    @pytest.mark.asyncio
    async def test_upload_strict_raises(self, mock_credential, monkeypatch):
        monkeypatch.setenv("INGESTION_STRICT_SCHEMA", "true")
        with patch("polling.ingestion.AzureLogsIngestionClient"):
            client = IngestionClient(mock_credential)
            with pytest.raises(SchemaValidationError):
                await client.upload(
                    dcr_id="dcr-123",
                    stream_name="Custom-Test_CL",
                    records=[{"a": 1, "extra": 2}],
                    expected_columns=["a"],
                )

    @pytest.mark.asyncio
    async def test_upload_no_records_is_noop(self, mock_credential):
        with patch("polling.ingestion.AzureLogsIngestionClient") as MockSdk:
            sdk = _make_sdk_mock()
            MockSdk.return_value = sdk
            client = IngestionClient(mock_credential)

            await client.upload(dcr_id="dcr-123", stream_name="S", records=[])
            sdk.upload.assert_not_called()

    @pytest.mark.asyncio
    async def test_upload_empty_dcr_raises(self, mock_credential):
        """Empty DCR-ID is a programming error; engine catches via fail-fast."""
        with patch("polling.ingestion.AzureLogsIngestionClient"):
            client = IngestionClient(mock_credential)
            with pytest.raises(ValueError, match="Empty DCR-ID"):
                await client.upload(dcr_id="", stream_name="S", records=[{"a": 1}])

    @pytest.mark.asyncio
    async def test_upload_empty_record_with_expected_columns(self, mock_credential):
        """[{}] must not be treated as 'empty' while expected_columns is set."""
        with patch("polling.ingestion.AzureLogsIngestionClient") as MockSdk:
            sdk = _make_sdk_mock()
            MockSdk.return_value = sdk
            client = IngestionClient(mock_credential)

            await client.upload(
                dcr_id="dcr-123",
                stream_name="S",
                records=[{}],
                expected_columns=["a"],
            )
            sdk.upload.assert_awaited_once()
            assert sdk.upload.call_args.kwargs["logs"] == [{}]

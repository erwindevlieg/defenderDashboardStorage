"""Tests voor HTTP-base helpers (Retry-After, backoff)."""

from polling.http_base import _backoff_with_jitter, _parse_retry_after


class TestParseRetryAfter:
    def test_none_falls_back_to_jitter(self):
        # Geen header → fallback waarde (>= 0, < cap).
        val = _parse_retry_after(None, attempt=0)
        assert 0 <= val <= 2 ** (0 + 1)

    def test_seconds_format(self):
        assert _parse_retry_after("5", attempt=0) == 5.0

    def test_seconds_clamped(self):
        # Bovengrens 300s zodat misconfigured upstream ons niet 1u laat slapen.
        assert _parse_retry_after("99999", attempt=0) == 300.0

    def test_seconds_negative_becomes_zero(self):
        assert _parse_retry_after("-3", attempt=0) == 0.0

    def test_http_date_format_in_past_yields_zero(self):
        # RFC 7231 HTTP-date in het verleden.
        assert _parse_retry_after("Wed, 21 Oct 2015 07:28:00 GMT", attempt=0) == 0.0

    def test_garbage_falls_back_to_jitter(self):
        val = _parse_retry_after("not-a-date-nor-seconds", attempt=1)
        # Mag niet crashen; geeft een redelijke wachttijd terug.
        assert 0 <= val <= 2 ** (1 + 1)


class TestBackoffWithJitter:
    def test_within_cap(self):
        for attempt in range(4):
            val = _backoff_with_jitter(attempt)
            assert 0 <= val <= 2 ** (attempt + 1)

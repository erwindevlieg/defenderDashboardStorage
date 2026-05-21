"""Tests voor de TokenCache."""

import time
from unittest.mock import MagicMock

from polling.auth import TokenCache

# Een ruim-in-de-toekomst expiratiestempel (24u verder) houdt de tests
# leesbaar en vermijdt magic numbers.
FAR_FUTURE = int(time.time()) + 86400


def _token(value: str, expires_on: float) -> MagicMock:
    """Maak een mock AccessToken-achtig object."""
    tok = MagicMock()
    tok.token = value
    tok.expires_on = expires_on
    return tok


class TestTokenCache:
    def test_first_call_fetches_token(self):
        cred = MagicMock()
        cred.get_token.return_value = _token("t1", FAR_FUTURE)
        cache = TokenCache(cred, "scope/.default")

        assert cache.get() == "t1"
        cred.get_token.assert_called_once_with("scope/.default")

    def test_second_call_uses_cache(self):
        cred = MagicMock()
        cred.get_token.return_value = _token("t1", FAR_FUTURE)
        cache = TokenCache(cred, "scope/.default")

        cache.get()
        cache.get()
        cache.get()
        assert cred.get_token.call_count == 1

    def test_refresh_when_within_margin(self):
        # Token verloopt over 60s, marge is 300s → moet altijd refreshen.
        cred = MagicMock()

        cred.get_token.side_effect = [
            _token("t1", time.time() + 60),
            _token("t2", time.time() + 9_999),
        ]
        cache = TokenCache(cred, "scope/.default", refresh_margin_seconds=300)

        assert cache.get() == "t1"
        assert cache.get() == "t2"
        assert cred.get_token.call_count == 2

    def test_invalidate_forces_refresh(self):
        cred = MagicMock()
        cred.get_token.side_effect = [
            _token("t1", FAR_FUTURE),
            _token("t2", FAR_FUTURE),
        ]
        cache = TokenCache(cred, "scope/.default")

        assert cache.get() == "t1"
        cache.invalidate()
        assert cache.get() == "t2"

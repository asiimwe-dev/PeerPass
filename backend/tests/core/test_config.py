"""Settings resolution from the environment."""

import pytest
from pydantic import ValidationError

from app.core.config import Settings

_MINIMAL = {
    "database_url": "postgresql+psycopg://peerpass@localhost/peerpass",
    "jwt_secret": "a-sufficiently-long-signing-key-for-tests",
}


def test_settings_resolve_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", _MINIMAL["database_url"])
    monkeypatch.setenv("JWT_SECRET", _MINIMAL["jwt_secret"])

    settings = Settings(_env_file=None)  # type: ignore[call-arg]

    assert settings.database_url == _MINIMAL["database_url"]


def test_missing_database_url_is_a_startup_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """No default, because an API that boots with no database is worse than one
    that refuses to start."""
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("JWT_SECRET", _MINIMAL["jwt_secret"])

    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_missing_signing_key_is_a_startup_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A default signing key would let anyone mint tokens for any account."""
    monkeypatch.setenv("DATABASE_URL", _MINIMAL["database_url"])
    monkeypatch.delenv("JWT_SECRET", raising=False)

    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


@pytest.mark.parametrize("placeholder", ["changeme", "secret", "replace-me"])
def test_placeholder_signing_key_is_refused(placeholder: str) -> None:
    """A committed `changeme` reaches production more often than anyone expects."""
    with pytest.raises(ValidationError):
        Settings(
            database_url=_MINIMAL["database_url"],
            jwt_secret=placeholder.ljust(40, "x"),
            _env_file=None,
        )


def test_short_signing_key_is_refused() -> None:
    with pytest.raises(ValidationError):
        Settings(
            database_url=_MINIMAL["database_url"],
            jwt_secret="too-short",
            _env_file=None,
        )


def test_cors_origins_accept_a_comma_separated_string() -> None:
    """A plain string is friendlier in a shell or a container manifest than
    embedded JSON."""
    settings = Settings(
        database_url=_MINIMAL["database_url"],
        jwt_secret=_MINIMAL["jwt_secret"],
        cors_origins="https://a.example, https://b.example",
        _env_file=None,
    )

    assert settings.cors_origins == ["https://a.example", "https://b.example"]


def test_cors_origins_default_to_empty() -> None:
    """The pilot is a mobile client, so no browser origin is trusted by default."""
    settings = Settings(
        database_url=_MINIMAL["database_url"],
        jwt_secret=_MINIMAL["jwt_secret"],
        _env_file=None,
    )

    assert settings.cors_origins == []


def test_access_token_lifetime_stays_short() -> None:
    """A long access token is what makes rotation untested in practice."""
    settings = Settings(
        database_url=_MINIMAL["database_url"],
        jwt_secret=_MINIMAL["jwt_secret"],
        _env_file=None,
    )

    assert settings.access_token_ttl <= 60
    assert settings.refresh_token_ttl > settings.access_token_ttl

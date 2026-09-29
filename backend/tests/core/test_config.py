"""Settings resolution from the environment."""

import pytest
from pydantic import ValidationError

from app.core.config import Settings

_MINIMAL = {
    "database_url": "postgresql+psycopg://peerpass@localhost/peerpass",
    "jwt_secret": "a-sufficiently-long-signing-key-for-tests",
    "token_pepper": "a-sufficiently-long-token-pepper-for-tests",
}

_A_REPLACED_SIGNING_KEY = "a-previously-used-signing-key-value-01"
_A_REPLACED_PEPPER = "a-previously-used-token-pepper-value-01"


def _settings(**overrides: object) -> Settings:
    """Build settings with the minimum required set, plus any overrides.

    A helper rather than repeating the required fields, because the required set
    growing is exactly the event these tests should notice: a test that
    constructs `Settings` by hand and omits a new required field fails loudly
    instead of quietly inheriting a value from the developer's `.env`.
    """
    values = {**_MINIMAL, **overrides}
    return Settings(**values, _env_file=None)  # type: ignore[call-arg]


# --- Required settings -------------------------------------------------------


def test_settings_resolve_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", _MINIMAL["database_url"])
    monkeypatch.setenv("JWT_SECRET", _MINIMAL["jwt_secret"])
    monkeypatch.setenv("TOKEN_PEPPER", _MINIMAL["token_pepper"])

    settings = Settings(_env_file=None)  # type: ignore[call-arg]

    assert settings.database_url == _MINIMAL["database_url"]
    assert settings.token_pepper == _MINIMAL["token_pepper"]


def test_missing_database_url_is_a_startup_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """No default, because an API that boots with no database is worse than one
    that refuses to start."""
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("JWT_SECRET", _MINIMAL["jwt_secret"])
    monkeypatch.setenv("TOKEN_PEPPER", _MINIMAL["token_pepper"])

    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_missing_signing_key_is_a_startup_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A default signing key would let anyone mint tokens for any account."""
    monkeypatch.setenv("DATABASE_URL", _MINIMAL["database_url"])
    monkeypatch.delenv("JWT_SECRET", raising=False)
    monkeypatch.setenv("TOKEN_PEPPER", _MINIMAL["token_pepper"])

    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_missing_token_pepper_is_a_startup_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Without a pepper, stored token hashes can be checked offline.

    An API that boots with no pepper is not a less secure one, it is a different
    kind of unsafe: a stolen database becomes a table of verifiable hashes
    instead of a table of opaque ones.
    """
    monkeypatch.setenv("DATABASE_URL", _MINIMAL["database_url"])
    monkeypatch.setenv("JWT_SECRET", _MINIMAL["jwt_secret"])
    monkeypatch.delenv("TOKEN_PEPPER", raising=False)

    with pytest.raises(ValidationError):
        Settings(_env_file=None)  # type: ignore[call-arg]


# --- S8: signing key rotation ------------------------------------------------


def test_s8_verification_set_is_the_primary_key_plus_the_retired_ones() -> None:
    settings = _settings(jwt_previous_secrets=[_A_REPLACED_SIGNING_KEY])

    assert settings.jwt_verification_secrets == [
        settings.jwt_secret,
        _A_REPLACED_SIGNING_KEY,
    ]


def test_s8_retired_keys_default_to_empty() -> None:
    """A fresh deployment trusts exactly one key, which is the whole point."""
    assert _settings().jwt_verification_secrets == [_MINIMAL["jwt_secret"]]


def test_s8_retired_keys_accept_a_comma_separated_string() -> None:
    """Same friendly form as CORS origins, for the same reason: a shell."""
    settings = _settings(
        jwt_previous_secrets=f"{_A_REPLACED_SIGNING_KEY}, another-retired-key-value"
    )

    assert settings.jwt_previous_secrets == [
        _A_REPLACED_SIGNING_KEY,
        "another-retired-key-value",
    ]


def test_s8_an_empty_retired_key_string_means_none() -> None:
    """A blank value must not become one retired key that is the empty string.

    A container manifest that sets `JWT_PREVIOUS_SECRETS=` to mean "nothing"
    would otherwise register an empty string as a key, and every token would be
    verified against it.
    """
    assert _settings(jwt_previous_secrets="").jwt_previous_secrets == []


def test_s8_retired_keys_may_come_from_the_environment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("DATABASE_URL", _MINIMAL["database_url"])
    monkeypatch.setenv("JWT_SECRET", _MINIMAL["jwt_secret"])
    monkeypatch.setenv("TOKEN_PEPPER", _MINIMAL["token_pepper"])
    monkeypatch.setenv("JWT_PREVIOUS_SECRETS", _A_REPLACED_SIGNING_KEY)

    settings = Settings(_env_file=None)  # type: ignore[call-arg]

    assert settings.jwt_previous_secrets == [_A_REPLACED_SIGNING_KEY]


# --- Secret hygiene ----------------------------------------------------------


@pytest.mark.parametrize("placeholder", ["changeme", "secret", "replace-me"])
def test_placeholder_signing_key_is_refused(placeholder: str) -> None:
    """A committed `changeme` reaches production more often than anyone expects."""
    with pytest.raises(ValidationError):
        _settings(jwt_secret=placeholder.ljust(40, "x"))


@pytest.mark.parametrize("placeholder", ["changeme", "secret", "replace-me"])
def test_placeholder_token_pepper_is_refused(placeholder: str) -> None:
    """The same guard on the second secret.

    Shared deliberately: both are secrets an operator has to invent, so both get
    the same protection against the same mistake.
    """
    with pytest.raises(ValidationError):
        _settings(token_pepper=placeholder.ljust(40, "x"))


def test_short_signing_key_is_refused() -> None:
    with pytest.raises(ValidationError):
        _settings(jwt_secret="too-short")


def test_short_token_pepper_is_refused() -> None:
    with pytest.raises(ValidationError):
        _settings(token_pepper="too-short")


def test_the_two_secrets_are_independently_configurable() -> None:
    """They protect different things and must rotate for different reasons.

    Sharing one value would mean rotating it takes out token signing and token
    hashing at the same time, and a developer who reuses one secret for a new
    service has also made both of them one compromise away from each other.
    """
    settings = _settings()

    assert settings.jwt_secret != settings.token_pepper


# --- Statement logging -------------------------------------------------------


def test_s2_statement_logging_is_allowed_in_development() -> None:
    assert _settings(environment="development", database_echo=True).database_echo


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_s2_statement_logging_is_refused_outside_development(
    environment: str,
) -> None:
    """`database_echo` logs SQL with its bound parameters.

    So the INSERT that creates an account is logged with the student's email and
    password hash, and the SELECT that signs one in is logged with the submitted
    address. On a platform that collects stdout, that is a durable copy of the
    credential table in whatever log store the operator uses. The failure mode is
    one `DATABASE_ECHO=true` in a manifest nobody re-reads, which is why this is
    a startup refusal and not a comment.
    """
    with pytest.raises(ValidationError):
        _settings(environment=environment, database_echo=True)


def test_s2_development_is_the_default_environment() -> None:
    """A fresh checkout runs locally with nothing configured.

    The default is the permissive one, so local setup cannot fail on a safety
    check. A deployment that turns it on has to say `production` explicitly,
    which is the moment the stricter rules start applying.
    """
    assert _settings().environment == "development"


def test_s2_an_unknown_environment_is_refused() -> None:
    """A typo has to fail rather than silently meaning something else.

    `environment='prod'` reading as development would quietly allow every
    development-only setting that is gated on it.
    """
    with pytest.raises(ValidationError):
        _settings(environment="prod")


# --- Transport ---------------------------------------------------------------


def test_cors_origins_accept_a_comma_separated_string() -> None:
    """A plain string is friendlier in a shell or a container manifest than
    embedded JSON."""
    settings = _settings(cors_origins="https://a.example, https://b.example")

    assert settings.cors_origins == ["https://a.example", "https://b.example"]


def test_cors_origins_default_to_empty() -> None:
    """The pilot is a mobile client, so no browser origin is trusted by default."""
    assert _settings().cors_origins == []


# --- Token lifetimes ---------------------------------------------------------


def test_access_token_lifetime_stays_short() -> None:
    """A long access token is what makes rotation untested in practice."""
    settings = _settings()

    assert settings.access_token_ttl <= 60
    assert settings.refresh_token_ttl > settings.access_token_ttl


# --- S1: Argon2id parameters -------------------------------------------------


def test_s1_argon2_defaults_sit_at_the_owasp_floor() -> None:
    settings = _settings()

    assert settings.password_hash_memory_kib == 19_456
    assert settings.password_hash_time_cost == 2
    assert settings.password_hash_parallelism == 1


def test_s1_a_weaker_memory_cost_is_refused() -> None:
    """Argon2 with almost no memory is barely slower to crack than a bare SHA-256.

    The bound is checked in configuration, not only in a test, so it cannot be
    lowered by an environment variable -- a value an operator sets is invisible
    in review. A test alone would stop the regression but still let the
    production instance be quietly weakened.
    """
    with pytest.raises(ValidationError):
        _settings(password_hash_memory_kib=19_455)


def test_s1_a_zero_time_cost_is_refused() -> None:
    with pytest.raises(ValidationError):
        _settings(password_hash_time_cost=0)


def test_s1_stronger_parameters_are_allowed() -> None:
    """The floor is a floor, not a ceiling. Raising it is the migration path."""
    assert _settings(password_hash_memory_kib=65_536).password_hash_memory_kib

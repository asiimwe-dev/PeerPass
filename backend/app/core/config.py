"""Application configuration.

Every value that differs between a developer's machine, CI, and a deployment
arrives from the environment. Nothing here has a default that would let the
service start in a state nobody intended: a missing database URL or a missing
signing key is a startup failure, not a warning, because an API that boots
without a signing key will happily issue tokens nobody can revoke.
"""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings, resolved from the environment or a local `.env`."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- Database -----------------------------------------------------------

    database_url: str = Field(
        description=(
            "SQLAlchemy URL for the primary database. Use the "
            "`postgresql+psycopg` driver, which is async-capable."
        )
    )

    database_echo: bool = Field(
        default=False,
        description="Log every statement. Never enable outside development.",
    )

    # --- Auth ---------------------------------------------------------------

    jwt_secret: str = Field(
        min_length=32,
        description=(
            "Signing key for access and refresh tokens. Must be at least 32 "
            "characters. Rotating it invalidates every issued token."
        ),
    )

    jwt_algorithm: str = Field(default="HS256")

    access_token_ttl: int = Field(
        default=15,
        ge=1,
        description="Access token lifetime in minutes. Kept short so that "
        "rotation is exercised rather than avoided.",
    )

    refresh_token_ttl: int = Field(
        default=30,
        ge=1,
        description="Refresh token lifetime in days.",
    )

    # --- Transport ----------------------------------------------------------

    cors_origins: list[str] = Field(
        default_factory=list,
        description="Allowed browser origins. Empty by default: the pilot is a "
        "mobile client, and an accidental wildcard here would expose the API "
        "to any site a student visits.",
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        """Accept a comma-separated string as well as a JSON list.

        `CORS_ORIGINS` is friendlier to set as a plain string in a shell or a
        container manifest than as embedded JSON.
        """
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @field_validator("jwt_secret")
    @classmethod
    def _reject_placeholder_secret(cls, value: str) -> str:
        """Refuse a secret that is obviously a placeholder.

        A committed `changeme` reaches production more often than anyone
        expects, and a weak signing key lets a third party mint tokens for any
        user.

        Matched as a prefix rather than the whole value, because the realistic
        shape is `changeme-change-me-in-production`, which satisfies the length
        rule and would otherwise sail through.
        """
        lowered = value.lower()
        if any(lowered.startswith(placeholder) for placeholder in _PLACEHOLDER_SECRETS):
            raise ValueError(
                f"jwt_secret starts with a placeholder ({lowered[:16]}...); "
                "supply a real key"
            )
        return value


_PLACEHOLDER_SECRETS = frozenset(
    {"changeme", "change-me", "secret", "replace", "replace-me", "development", "test"}
)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """The process-wide settings.

    Cached so the environment is parsed once and every module sees the same
    values; `get_settings.cache_clear()` exists for tests that need to vary it.
    """
    return Settings()  # type: ignore[call-arg]

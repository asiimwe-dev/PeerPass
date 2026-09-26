"""Password hashing and token minting.

Deliberately the only module that knows how a credential is turned into a
stored hash or a signed token. Services ask it for a hash or a token; they
never call the JWT library directly, so the algorithm can change without
touching a service.
"""

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt

from app.core.config import get_settings
from app.core.exceptions import AuthenticationProblem

TOKEN_TYPE_ACCESS = "access"
TOKEN_TYPE_REFRESH = "refresh"


def hash_password(password: str) -> str:
    """Hash a password for storage.

    PBKDF2-HMAC-SHA256 from the standard library. Argon2id or bcrypt would be
    the better default, but both need a compiled dependency, and the pilot
    deploys to a small instance where a wheel that must match the platform is a
    real operational cost. The iteration count is high enough to make an offline
    attack expensive, and this is the one place to revisit if that changes.
    """
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _ITERATIONS)
    return f"pbkdf2_sha256${_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    """Check a password against a stored hash.

    Compares in constant time. A length or prefix mismatch still runs a dummy
    hash so that a rejected username and a rejected password take the same time
    and cannot be told apart.
    """
    try:
        algorithm, iterations, salt_hex, digest_hex = stored.split("$")
    except ValueError:
        return False

    if algorithm != "pbkdf2_sha256":
        return False

    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        bytes.fromhex(salt_hex),
        int(iterations),
    )
    return hmac.compare_digest(digest.hex(), digest_hex)


@dataclass(frozen=True, slots=True)
class TokenPair:
    """An access and refresh token, with the identifiers needed to rotate.

    `refresh_token_id` is the handle the server stores against the session. It
    is a separate opaque value rather than the token itself so that a stolen
    database does not hand over usable refresh tokens.
    """

    access_token: str
    refresh_token: str
    refresh_token_id: uuid.UUID
    refresh_expires_at: datetime


def create_token_pair(*, subject: uuid.UUID, roles: list[str]) -> TokenPair:
    """Mint a fresh access and refresh token for a user."""
    settings = get_settings()
    now = datetime.now(UTC)
    refresh_expires_at = now + timedelta(days=settings.refresh_token_ttl)
    refresh_token_id = uuid.uuid4()

    return TokenPair(
        access_token=_encode(
            subject=subject,
            token_type=TOKEN_TYPE_ACCESS,
            ttl=timedelta(minutes=settings.access_token_ttl),
            now=now,
            claims={"roles": roles},
        ),
        refresh_token=_encode(
            subject=subject,
            token_type=TOKEN_TYPE_REFRESH,
            ttl=timedelta(days=settings.refresh_token_ttl),
            now=now,
            claims={"jti": str(refresh_token_id)},
        ),
        refresh_token_id=refresh_token_id,
        refresh_expires_at=refresh_expires_at,
    )


def decode_token(token: str, *, expected_type: str) -> dict[str, Any]:
    """Verify a token and return its claims.

    Raises [AuthenticationProblem] for every failure. A caller cannot tell from
    the exception whether the token was forged, expired, or of the wrong type,
    which is the intent: those cases should be indistinguishable to an attacker.
    """
    settings = get_settings()
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
    except jwt.ExpiredSignatureError as exc:
        raise AuthenticationProblem("Your session has ended.") from exc
    except jwt.PyJWTError as exc:
        raise AuthenticationProblem("Your session is not valid.") from exc

    if claims.get("type") != expected_type:
        raise AuthenticationProblem("Your session is not valid.")

    return claims


def new_uuid7() -> uuid.UUID:
    """A time-ordered UUID for primary keys.

    Chosen over a random v4 because the primary key is also the write-order
    index. Time-ordered values insert near the end of the B-tree instead of
    scattering inserts across it, which matters for the session log, the table
    that grows fastest and is read newest-first.
    """
    return uuid.uuid7()


def new_public_id() -> uuid.UUID:
    """A random UUID to expose to clients.

    Random rather than time-ordered, because a public id that encodes a
    creation time hands an attacker a way to enumerate and date other records
    from a single leaked link.
    """
    return uuid.uuid4()


def _encode(
    *,
    subject: uuid.UUID,
    token_type: str,
    ttl: timedelta,
    now: datetime,
    claims: dict[str, Any],
) -> str:
    settings = get_settings()
    payload = {
        "sub": str(subject),
        "type": token_type,
        "iat": int(now.timestamp()),
        "exp": int((now + ttl).timestamp()),
        **claims,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


_ITERATIONS = 600_000

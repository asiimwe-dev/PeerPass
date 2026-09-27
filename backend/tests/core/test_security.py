"""Password hashing, token minting, and identifier generation."""

import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from jwt import ExpiredSignatureError

from app.core import security
from app.core.exceptions import AuthenticationProblem


def test_hash_password_produces_a_self_describing_hash() -> None:
    stored = security.hash_password("correct horse battery staple")

    algorithm, iterations, salt, digest = stored.split("$")

    assert algorithm == "pbkdf2_sha256"
    assert int(iterations) >= 100_000
    assert salt and digest


def test_hash_password_never_stores_the_password() -> None:
    stored = security.hash_password("correct horse battery staple")

    assert "correct horse battery staple" not in stored


def test_hash_password_salts_so_equal_passwords_differ() -> None:
    first = security.hash_password("same password")
    second = security.hash_password("same password")

    assert first != second


def test_verify_password_accepts_the_original_password() -> None:
    stored = security.hash_password("correct horse battery staple")

    assert security.verify_password("correct horse battery staple", stored)


def test_verify_password_rejects_a_wrong_password() -> None:
    stored = security.hash_password("correct horse battery staple")

    assert not security.verify_password("wrong password", stored)


@pytest.mark.parametrize(
    "malformed",
    ["", "notahash", "pbkdf2_sha256$only-three-parts", "md5$1$aa$bb"],
)
def test_verify_password_rejects_a_malformed_hash(malformed: str) -> None:
    """A corrupt stored value must fail closed, not raise.

    Returning False rather than propagating matters: a row with a legacy or
    corrupt hash should deny access, not take the service down.
    """
    assert not security.verify_password("anything", malformed)


def test_create_token_pair_mints_distinct_access_and_refresh_tokens() -> None:
    user_id = uuid.uuid4()

    pair = security.create_token_pair(subject=user_id, roles=["student"])

    assert pair.access_token != pair.refresh_token
    assert isinstance(pair.refresh_token_id, uuid.UUID)


def test_decode_token_returns_claims_for_the_right_type() -> None:
    user_id = uuid.uuid4()
    pair = security.create_token_pair(subject=user_id, roles=["student", "tutor"])

    claims = security.decode_token(pair.access_token, expected_type="access")

    assert claims["sub"] == str(user_id)
    assert claims["type"] == "access"
    assert claims["roles"] == ["student", "tutor"]


def test_decode_token_rejects_a_refresh_token_used_as_an_access_token() -> None:
    """Type confusion is the whole point of the `type` claim.

    Without it, the long-lived refresh token would work as an access token and
    rotation would be pointless.
    """
    pair = security.create_token_pair(subject=uuid.uuid4(), roles=["student"])

    with pytest.raises(AuthenticationProblem):
        security.decode_token(pair.refresh_token, expected_type="access")


def test_decode_token_rejects_a_token_signed_with_another_key() -> None:
    forged = jwt.encode(
        {
            "sub": str(uuid.uuid4()),
            "type": "access",
            "exp": int((datetime.now(UTC) + timedelta(hours=1)).timestamp()),
        },
        "a-completely-different-signing-key-value",
        algorithm="HS256",
    )

    with pytest.raises(AuthenticationProblem):
        security.decode_token(forged, expected_type="access")


def test_decode_token_rejects_an_expired_token() -> None:
    expired = jwt.encode(
        {
            "sub": str(uuid.uuid4()),
            "type": "access",
            "exp": int((datetime.now(UTC) - timedelta(hours=1)).timestamp()),
        },
        security.get_settings().jwt_secret,
        algorithm="HS256",
    )

    with pytest.raises(ExpiredSignatureError):
        jwt.decode(expired, security.get_settings().jwt_secret, algorithms=["HS256"])

    with pytest.raises(AuthenticationProblem):
        security.decode_token(expired, expected_type="access")


def test_refresh_token_carries_the_handle_used_to_rotate_it() -> None:
    pair = security.create_token_pair(subject=uuid.uuid4(), roles=["student"])

    claims = security.decode_token(pair.refresh_token, expected_type="refresh")

    assert claims["jti"] == str(pair.refresh_token_id)


def test_new_uuid7_is_time_ordered() -> None:
    """Time-ordered keys keep inserts at the end of the primary-key index."""
    generated = [security.new_uuid7() for _ in range(50)]

    assert generated == sorted(generated)


def test_new_public_id_is_version_4() -> None:
    """A public id must not encode its creation time.

    A time-ordered public id would let a single leaked link be used to date and
    enumerate other records.
    """
    assert security.new_public_id().version == 4

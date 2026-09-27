"""Account schemas: registration, sign-in, and the caller's own profile.

`password_hash` has no field anywhere in this package and must not gain one. A
response schema is the easiest place for a secret to leak, because adding the
attribute is one line and nothing fails until someone reads the payload.
"""

import uuid
from datetime import datetime

from pydantic import EmailStr, Field, field_validator

from app.models.enums import UserRole
from app.schemas.base import OrmSchema, RequestSchema, Trimmed

#: Deliberately generous on the low end, because a Ugandan name may be two words
#: and an initial, and rejecting a real student over a naming convention is worse
#: than storing a slightly untidy one.
MIN_FULL_NAME_LENGTH = 2
MAX_FULL_NAME_LENGTH = 160

MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128


class RegisterRequest(RequestSchema):
    """A new account.

    The password minimum is higher than most services use, and deliberately so:
    a peer-tutoring account is tied to a real person's verified academic record,
    and the pilot's threat model is an attacker who has a list of student emails
    rather than a password-spraying bot. Length beats composition rules, so there
    is no required-symbol rule -- it produces `Passw0rd!` and teaches nothing.
    """

    email: EmailStr
    full_name: Trimmed = Field(
        min_length=MIN_FULL_NAME_LENGTH, max_length=MAX_FULL_NAME_LENGTH
    )
    password: str = Field(
        min_length=MIN_PASSWORD_LENGTH, max_length=MAX_PASSWORD_LENGTH
    )
    university_id: uuid.UUID | None = Field(
        default=None,
        description="The public id of the user's university.",
    )
    roles: list[UserRole] = Field(
        default_factory=list,
        description=(
            "Roles requested at sign-up. A user may hold several, and the tutor "
            "role is only granted once competencies are verified, so requesting "
            "it here records intent rather than granting it."
        ),
    )

    @field_validator("password")
    @classmethod
    def reject_whitespace_only_password(cls, value: str) -> str:
        """Reject a password of all spaces.

        Length checks alone are fooled by `"                "`. PBKDF2 would hash
        it happily and the account would have no real secret, which is exactly
        the account an attacker creates first.
        """
        if not value.strip():
            raise ValueError("password must not be only whitespace")
        return value

    @field_validator("roles")
    @classmethod
    def reject_duplicate_roles(cls, value: list[UserRole]) -> list[UserRole]:
        """Collapse duplicates instead of failing.

        The join table's primary key rejects them anyway; collapsing here means
        the client gets a clear field-level message rather than a 409 for
        something it can fix on its own.
        """
        return list(dict.fromkeys(value))


class LoginRequest(RequestSchema):
    """Credentials.

    `email` is not normalised to lower case here. Registration lowercases it (see
    `app.services.auth`), and normalising on only one side would make an account
    sign in successfully under one spelling and fail under another.
    """

    email: EmailStr
    password: str = Field(max_length=MAX_PASSWORD_LENGTH)


class RefreshRequest(RequestSchema):
    """A refresh token presented for exchange.

    The token arrives in the body rather than a cookie, because the pilot client
    is a mobile app with no cookie jar, and a cookie would add CSRF handling for
    no benefit.
    """

    refresh_token: str = Field(min_length=1, max_length=4096)


class UserResponse(OrmSchema):
    """A user as the client sees them.

    `id` is the public id. There is no `user_id`, and nothing here exposes a
    primary key, `password_hash`, or an email consent timestamp -- the last being
    the caller's own record to see, but not another user's.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    email: EmailStr
    full_name: str
    roles: list[UserRole]
    university_id: uuid.UUID | None = Field(
        default=None, validation_alias="university_public_id"
    )
    is_active: bool
    created_at: datetime


class CurrentUserResponse(OrmSchema):
    """The signed-in user's own record.

    A separate schema from `UserResponse` rather than a flag, because the two
    differ in what they expose and a flag invites the difference to be applied
    by whoever remembers. Both are built from the same model; only this one is
    allowed to carry the consent timestamp.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    email: EmailStr
    full_name: str
    roles: list[UserRole]
    university_id: uuid.UUID | None = Field(
        default=None, validation_alias="university_public_id"
    )
    academic_data_consented_at: datetime | None = None
    created_at: datetime


class TokenResponse(OrmSchema):
    """A freshly issued token pair.

    `token_type` is `Bearer` because the client sends `Authorization: Bearer
    <access_token>`, and making the value part of the payload means a client
    cannot get that header subtly wrong.
    """

    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int = Field(description="Access token lifetime in seconds.")


class AuthResponse(OrmSchema):
    """Tokens plus the user they belong to.

    Together rather than two calls, so the client is never holding a valid token
    it cannot yet render a name for.
    """

    tokens: TokenResponse
    user: CurrentUserResponse

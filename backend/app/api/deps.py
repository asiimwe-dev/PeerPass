"""Request dependencies: the database session and the authenticated caller.

Nothing here decides anything. Resolving a token into a user is wiring, and the
rules that would make it more than wiring -- what counts as a valid token, when
a session has ended -- are in `app.core.security` and `app.services.auth`. A
dependency that starts making decisions is a rule that has to be tested twice.
"""

import uuid
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.exceptions import AuthenticationProblem
from app.core.security import TOKEN_TYPE_ACCESS, decode_token
from app.models.enums import UserRole
from app.models.user import User, load_roles
from app.services import auth_service

#: `auto_error=False` so a missing header reaches the same failure path as a
#: malformed one. Left at the default, FastAPI raises its own 403 for an absent
#: header, which would make "not signed in" and "your token is bad" two
#: different status codes for the same situation.
_bearer = HTTPBearer(auto_error=False)

DatabaseSession = Annotated[AsyncSession, Depends(get_db)]


@dataclass(frozen=True, slots=True)
class AuthenticatedUser:
    """The caller, with the roles this request was evaluated against.

    A pair rather than a bare `User` because the role is needed on almost every
    authorisation check, and reaching for it through the join table at each call
    site would put the same query in five places.
    """

    user: User
    roles: frozenset[UserRole]

    @property
    def is_tutee(self) -> bool:
        return UserRole.STUDENT in self.roles

    @property
    def is_tutor(self) -> bool:
        return UserRole.TUTOR in self.roles


def _bearer_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> str:
    """The access token on this request, or a 401."""
    if credentials is None or not credentials.credentials:
        raise AuthenticationProblem()
    return credentials.credentials


async def get_current_user(
    db: DatabaseSession,
    token: Annotated[str, Depends(_bearer_token)],
) -> AuthenticatedUser:
    """The signed-in caller, or a 401.

    Roles are read from the database on every request rather than taken from the
    token, and that is why the access token carries no role claim. A suspended
    tutor's next request reflects the suspension immediately instead of whenever
    their token happens to expire, and revoking access does not mean waiting out
    a 15 minute lifetime.

    The token's own type is checked on the way in. Without that check a refresh
    token would be accepted wherever an access token is expected, and a refresh
    token is a 30 day credential -- it would quietly turn every authenticated
    endpoint into a month-long session.

    This is also where a deleted account is refused, on every route at once. Any
    other check would have to be repeated per route, and one route that forgot it
    would hand a tombstone a live session for the remaining lifetime of its
    token.
    """
    claims = decode_token(token, expected_type=TOKEN_TYPE_ACCESS)
    user = await auth_service.load_user_by_public_id(db, uuid.UUID(claims["sub"]))

    if not user.is_active:
        # A deactivated account's token is cryptographically valid, so without
        # this it would keep working until it expired. Deactivation is the one
        # thing that must not wait for a timeout.
        raise AuthenticationProblem()

    if user.is_deleted:
        # Checked separately from `is_active` even though deletion sets both, so
        # that the rule reads as one statement in one place. Deletion also sets
        # `is_active = False` to fail closed against any future path that only
        # knows about `is_active`; if that flag is ever restored, this still
        # refuses. The person asked to stop existing, and their unexpired token
        # is not a reason to keep serving them.
        raise AuthenticationProblem()

    return AuthenticatedUser(user=user, roles=frozenset(await load_roles(db, user.id)))


#: The authenticated caller, for a route that needs one.
CurrentUser = Annotated[AuthenticatedUser, Depends(get_current_user)]


async def require_admin(caller: CurrentUser) -> AuthenticatedUser:
    """Allow only explicitly provisioned administrators."""
    if UserRole.ADMIN not in caller.roles:
        from app.core.exceptions import AuthorizationProblem

        raise AuthorizationProblem()
    return caller


AdminUser = Annotated[AuthenticatedUser, Depends(require_admin)]

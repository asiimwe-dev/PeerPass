"""The caller's own profile.

Only `/me` exists. Every other user-visible route -- a public profile, a search
over students -- is deliberately absent, and adding one is a decision about
what a student can see about another, not a mechanical addition.
"""

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.user import CurrentUserResponse, UpdateProfileRequest
from app.services import auth_service, deletion_service

router = APIRouter(prefix="/users", tags=["users"])


@router.patch("/me", response_model=CurrentUserResponse, summary="Update my profile")
async def update_my_profile(
    payload: UpdateProfileRequest, caller: CurrentUser, db: DatabaseSession
) -> CurrentUserResponse:
    """Apply the onboarding wizard's step.

    PATCH rather than PUT because the wizard saves one step at a time and each
    step sends only the fields it collected. A PUT would have to require the
    whole profile, so a step that had not been reached yet would have to be sent
    as null and would erase what an earlier step had just saved.

    Consent is recorded here and cannot be withdrawn here. See
    `UpdateProfileRequest.academic_data_consented`.
    """
    return await auth_service.update_profile(db, caller.user, payload)


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete my account",
)
async def delete_my_account(caller: CurrentUser, db: DatabaseSession) -> None:
    """Anonymise the caller's account.

    204, and no body, because there is nothing left to describe. The account is
    not gone: the row survives as a tombstone so that sessions, ratings,
    endorsements and competencies keep counting, which means there is no
    representation of "your account as it is now" worth returning. A 200 with the
    scrubbed profile would be actively misleading -- it would hand back a
    `deleted+...@deleted.invalid` address and an empty name as though they were
    a real profile. The 204 itself is the whole confirmation, and the client's
    next action is to discard its session, which it already knows to do.

    No body also means no response schema to keep in step with the tombstone's
    address, which `EmailStr` would refuse to serialise anyway.
    """
    await deletion_service.delete_account(db, caller.user)

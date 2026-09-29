"""The caller's own profile.

Only `/me` exists. Every other user-visible route -- a public profile, a search
over students -- is deliberately absent, and adding one is a decision about
what a student can see about another, not a mechanical addition.
"""

from fastapi import APIRouter

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.user import CurrentUserResponse, UpdateProfileRequest
from app.services import auth_service

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

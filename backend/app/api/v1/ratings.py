"""Post-session rating routes."""

import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.rating import RatingCreate, RatingResponse, TutorRatingSummary
from app.services import rating_service

router = APIRouter(prefix="/ratings", tags=["ratings"])
session_router = APIRouter(prefix="/sessions", tags=["ratings"])


@router.get("/me", response_model=TutorRatingSummary, summary="My tutor rating summary")
async def my_rating_summary(
    caller: CurrentUser,
    db: DatabaseSession,
) -> TutorRatingSummary:
    """Current tutor's aggregate summary."""
    return await rating_service.get_tutor_rating_summary(db, caller.user)


@router.post(
    "/{session_id}",
    response_model=RatingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Rate a completed session",
)
async def submit_rating_for_session(
    session_id: uuid.UUID,
    payload: RatingCreate,
    caller: CurrentUser,
    db: DatabaseSession,
) -> RatingResponse:
    """Create or update a rating for a completed session."""
    return await rating_service.submit_rating(db, caller.user, session_id, payload)


@router.post(
    "/{session_id}/ratings",
    response_model=RatingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Rate a completed session",
)
async def submit_rating_for_session_nested(
    session_id: uuid.UUID,
    payload: RatingCreate,
    caller: CurrentUser,
    db: DatabaseSession,
) -> RatingResponse:
    """Compatibility alias for a session-scoped rating route."""
    return await rating_service.submit_rating(db, caller.user, session_id, payload)


@session_router.post(
    "/{session_id}/ratings",
    response_model=RatingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Rate a completed session",
)
async def submit_rating_for_session_session_scoped(
    session_id: uuid.UUID,
    payload: RatingCreate,
    caller: CurrentUser,
    db: DatabaseSession,
) -> RatingResponse:
    """Session-scoped route for rating wrappers and mobile clients."""
    return await rating_service.submit_rating(db, caller.user, session_id, payload)


@router.get(
    "/me/recent", response_model=list[RatingResponse], summary="Recent tutor ratings"
)
async def my_recent_ratings(
    caller: CurrentUser,
    db: DatabaseSession,
) -> list[RatingResponse]:
    """Recent ratings received by the current tutor."""
    return await rating_service.list_recent_ratings(db, caller.user)

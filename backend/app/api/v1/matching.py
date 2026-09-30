"""Topic request and tutor matching routes."""

import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.matching import MatchRequest, MatchResponse
from app.schemas.session import HelpRequestCreate, HelpRequestResponse
from app.services import matching_service

router = APIRouter(prefix="/matching", tags=["matching"])


@router.post(
    "/help-requests",
    response_model=HelpRequestResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a help request",
)
async def create_help_request(
    payload: HelpRequestCreate,
    caller: CurrentUser,
    db: DatabaseSession,
) -> HelpRequestResponse:
    """Create a help request for a course unit and topic."""
    return await matching_service.create_help_request(db, caller.user, payload)


@router.get(
    "/help-requests/me",
    response_model=list[HelpRequestResponse],
    summary="My help requests",
)
async def list_help_requests(
    caller: CurrentUser,
    db: DatabaseSession,
) -> list[HelpRequestResponse]:
    """List the signed-in user's help requests."""
    return await matching_service.list_help_requests(db, caller.user)


@router.post(
    "/suggestions",
    response_model=MatchResponse,
    summary="Find tutors for a course unit",
)
@router.post(
    "",
    response_model=MatchResponse,
    summary="Find tutors for a course unit",
)
async def match_tutors(
    payload: MatchRequest,
    caller: CurrentUser,
    db: DatabaseSession,
) -> MatchResponse:
    """Find tutors for the supplied course unit."""
    return await matching_service.match_tutors(db, caller.user, payload)


@router.post(
    "/help-requests/{request_id}/matches",
    response_model=MatchResponse,
    summary="Find tutors for one help request",
)
async def match_request_tutors(
    request_id: uuid.UUID,
    payload: MatchRequest,
    caller: CurrentUser,
    db: DatabaseSession,
) -> MatchResponse:
    """Find tutors matching an existing help request."""
    return await matching_service.match_request_tutors(
        db,
        caller.user,
        request_id,
        payload,
    )


@router.get(
    "/help-requests/{request_id}",
    response_model=HelpRequestResponse,
    summary="Load one help request",
)
async def get_help_request(
    request_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
) -> HelpRequestResponse:
    """Fetch one help request the student owns."""
    request = await matching_service._load_help_request(db, caller.user, request_id)
    return matching_service._help_request_response(request)

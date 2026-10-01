"""Topic request and tutor matching routes."""

import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.matching import MatchRequest, MatchResponse
from app.schemas.session import (
    HelpRequestCreate,
    HelpRequestResponse,
    SelectTutorRequest,
)
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


# Declared before `/help-requests/{request_id}` below. FastAPI matches in
# declaration order, so a path segment that is not a UUID has to be claimed here or
# it reaches the parameterised route and comes back as a 422 for a path that
# exists.
@router.get(
    "/help-requests/awaiting-me",
    response_model=list[HelpRequestResponse],
    summary="Requests waiting on my confirmation",
)
async def list_requests_awaiting_confirmation(
    caller: CurrentUser,
    db: DatabaseSession,
) -> list[HelpRequestResponse]:
    """The help requests that named this user and are waiting on their answer.

    The tutor's half of the choice: a student picks, and the tutor they picked
    decides. Without this a tutor has no way to learn that they were chosen, which
    would leave the student waiting on a decision nobody was ever shown.
    """
    return await matching_service.list_requests_awaiting_confirmation(db, caller.user)


@router.post(
    "/help-requests/{request_id}/select",
    response_model=HelpRequestResponse,
    summary="Choose a tutor for one help request",
)
async def select_tutor_for_request(
    request_id: uuid.UUID,
    payload: SelectTutorRequest,
    caller: CurrentUser,
    db: DatabaseSession,
) -> HelpRequestResponse:
    """Choose the tutor a request should wait on.

    The tutor named in the body is re-checked against the request's own course
    unit rather than taken on trust: the client is choosing from a list, and the
    list it was given proves nothing about what that client sends next.
    """
    return await matching_service.select_tutor_for_request(
        db,
        caller.user,
        request_id,
        payload,
    )


@router.post(
    "/help-requests/{request_id}/decline",
    response_model=HelpRequestResponse,
    summary="Decline a help request that named me",
)
async def decline_help_request(
    request_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
) -> HelpRequestResponse:
    """Turn down a request that is waiting on this user.

    The other half of the student's choice, and a decision that stays recorded:
    a declined request is not the same as one nobody answered, and the student
    reads the two differently.
    """
    return await matching_service.decline_help_request(db, caller.user, request_id)


@router.post(
    "/suggestions",
    response_model=MatchResponse,
    summary="Find tutors for a course unit",
)
async def match_tutors(
    payload: MatchRequest,
    caller: CurrentUser,
    db: DatabaseSession,
) -> MatchResponse:
    """Find tutors for the supplied course unit.

    One path for this handler. It used to be registered twice, at
    `/matching/suggestions` and at `/matching`, and two URLs for one handler
    means two things to keep working: a client's base URL decides which one it
    calls, so a change to either would break half the installed apps, and the
    route table stops being a description of the API. `/suggestions` is the
    canonical path because it says what the response is.

    `request_id` comes back null. Nothing backs a unit-only query, and the field
    names a help request the client could go and open.
    """
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
    """Find tutors matching an existing help request.

    Answers for the course unit *that request* was created for. A body naming a
    different unit is a 422 rather than something quietly ignored: this handler
    used to match whatever unit the body carried, so a client asking "who can
    take this request" was answered about another course entirely.
    """
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
    """Fetch one help request the student owns.

    One public service call: the ownership check and the response shape are one
    decision, and a route assembling the body out of the service's internals
    could skip the check by reaching for the other half.
    """
    return await matching_service.get_help_request(db, caller.user, request_id)

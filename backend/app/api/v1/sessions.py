"""Tutoring session scheduling and logging routes."""

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.message import (
    MessageCreate,
    MessageResponse,
    MessagesReadResponse,
)
from app.schemas.session import (
    SessionCreate,
    SessionResponse,
    SessionTransitionRequest,
)
from app.services import message_service, session_service

router = APIRouter(prefix="/sessions", tags=["sessions"])


@router.post(
    "",
    response_model=SessionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create an accepted tutoring session",
)
async def create_session(
    payload: SessionCreate,
    caller: CurrentUser,
    db: DatabaseSession,
) -> SessionResponse:
    """Accept a matched request and create the live tutoring session."""
    return await session_service.create_session(db, caller.user, payload)


@router.get(
    "/me",
    response_model=list[SessionResponse],
    summary="My sessions",
)
async def list_sessions(
    caller: CurrentUser,
    db: DatabaseSession,
) -> list[SessionResponse]:
    """Every session the current user is part of."""
    return await session_service.list_sessions(db, caller.user)


@router.get(
    "/{session_id}",
    response_model=SessionResponse,
    summary="Load one session",
)
async def get_session(
    session_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
) -> SessionResponse:
    """Fetch a specific session that belongs to the caller."""
    return await session_service.get_session(db, caller.user, session_id)


@router.get(
    "/{session_id}/messages",
    response_model=list[MessageResponse],
    summary="Read a session's messages",
)
async def list_messages(
    session_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
    after: Annotated[
        uuid.UUID | None,
        Query(description="Return only messages after this one, for polling."),
    ] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = message_service.DEFAULT_PAGE_LIMIT,
) -> list[MessageResponse]:
    """The thread between the two parties, oldest first.

    A query parameter rather than a header for the cursor: it is a plain read,
    it belongs in a link as much as in a poll, and the client can reproduce it
    from the last message it holds.
    """
    return await message_service.list_messages(
        db,
        caller.user,
        session_id,
        after=after,
        limit=limit,
    )


@router.post(
    "/{session_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Send a message in a session",
)
async def send_message(
    session_id: uuid.UUID,
    payload: MessageCreate,
    caller: CurrentUser,
    db: DatabaseSession,
) -> MessageResponse:
    """Add one message, addressed to the other party by the session itself.

    There is no recipient field: on a session there are exactly two people, and
    the caller is one of them, so the recipient is the other one. A body that
    could name a recipient would be a way to write to someone the app never
    matched the sender with.
    """
    return await message_service.send_message(db, caller.user, session_id, payload)


@router.post(
    "/{session_id}/messages/read",
    response_model=MessagesReadResponse,
    summary="Mark a session's messages read",
)
async def mark_messages_read(
    session_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
) -> MessagesReadResponse:
    """Clear the caller's own unread messages in this thread.

    Idempotent, and scoped to what the other party wrote, so a thread marked
    read twice reports zero the second time rather than an error.
    """
    return await message_service.mark_read(db, caller.user, session_id)


@router.post(
    "/{session_id}/transition",
    response_model=SessionResponse,
    summary="Cancel or mark a session as a no-show",
)
async def transition_session(
    session_id: uuid.UUID,
    payload: SessionTransitionRequest,
    caller: CurrentUser,
    db: DatabaseSession,
) -> SessionResponse:
    """Cancel a session or record that it did not happen.

    Starting and completing are deliberately not transitions: they are
    `check-in` and `finish`, called by both parties, so no single account can
    move a session to a state that claims the other person was present.
    """
    return await session_service.transition_session(
        db,
        caller.user,
        session_id,
        payload,
    )


@router.post(
    "/{session_id}/check-in",
    response_model=SessionResponse,
    summary="Record your arrival for a session",
)
async def check_in(
    session_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
) -> SessionResponse:
    """One party's half of the start handshake.

    The session goes live when both parties have called this. Repeating the
    call is harmless: it does not move the timestamp a second time and does not
    report an error for a check-in that already happened.
    """
    return await session_service.check_in(db, caller.user, session_id)


@router.post(
    "/{session_id}/finish",
    response_model=SessionResponse,
    summary="Record your departure from a session",
)
async def finish(
    session_id: uuid.UUID,
    caller: CurrentUser,
    db: DatabaseSession,
) -> SessionResponse:
    """One party's half of the completion handshake.

    The session completes when both parties have called this, and only then are
    the minutes banked. The elapsed time is the window both were present, so one
    party cannot extend the session after the other has left.
    """
    return await session_service.finish(db, caller.user, session_id)

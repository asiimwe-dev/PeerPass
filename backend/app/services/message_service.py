"""The conversation between the two parties of one session.

There is no conversation resource of its own. A thread *is* the session: the
session decides who is allowed to write (only the two people named on it) and
what it is about (the topic one of them asked for). A separate `conversations`
table would have to duplicate both answers, and the two copies would eventually
disagree -- for instance when a session is cancelled and one table still says
the thread is open.

Three operations, one per thing a chat screen does: read the thread (and keep
reading it, which is why the read takes an `after` cursor), write one message,
and mark what the other person wrote as read. Sending is the only write that
creates a row, and it is the one that can notify the other party.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.exceptions import AuthorizationProblem, ConflictProblem, NotFoundProblem
from app.models.enums import SessionStatus
from app.models.message import SessionMessage
from app.models.session import Session
from app.models.user import User
from app.schemas.message import MessageCreate, MessageResponse, MessagesReadResponse
from app.services import notification_service

#: How much of a message the inbox preview shows. Long enough to carry a venue
#: and a time, short enough that the bell is still a summary.
PREVIEW_LENGTH = 160

#: A poll asks for what arrived since the last message it saw, so the page is
#: normally empty or one or two rows. The ceiling is what stops a first open of a
#: very long thread from returning thousands.
DEFAULT_PAGE_LIMIT = 50


def _utc(value: datetime) -> datetime:
    """Normalize to UTC so SQLite and PostgreSQL compare the same instant."""
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


async def _load_session_for_party(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
) -> Session:
    """The session, if the caller is one of its two parties.

    Deliberately reads only the session row. Messages need the two party ids and
    the status, and loading the tutor's profile behind a thread read would put
    the cost of a screen the caller is not looking at on this one.
    """
    session = await db.scalar(select(Session).where(Session.public_id == session_id))
    if session is None:
        raise NotFoundProblem("That session could not be found.")
    if session.tutee_id != user.id and session.tutor_id != user.id:
        raise AuthorizationProblem("You are not part of that session.")
    return session


async def list_messages(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
    *,
    after: uuid.UUID | None = None,
    limit: int = DEFAULT_PAGE_LIMIT,
) -> list[MessageResponse]:
    """The thread, oldest first, optionally only what came after [after].

    `after` names a message the client already has, not a timestamp. A client
    that sent the newest message it holds gets exactly the gap, and it cannot
    accidentally skip a row that shares a timestamp with the one it named: the
    comparison is on the `(created_at, id)` pair, not on the clock alone.

    Without `after` the newest page is returned, still in reading order. A fresh
    open shows the most recent exchange rather than the first fifty lines the
    two people ever wrote.
    """
    session = await _load_session_for_party(db, user, session_id)

    query = (
        select(SessionMessage)
        .where(SessionMessage.session_id == session.id)
        .options(
            selectinload(SessionMessage.sender),
            selectinload(SessionMessage.session),
        )
    )

    if after is not None:
        anchor = await _load_anchor(db, session, after)
        query = query.where(
            or_(
                SessionMessage.created_at > anchor.created_at,
                and_(
                    SessionMessage.created_at == anchor.created_at,
                    SessionMessage.id > anchor.id,
                ),
            )
        ).order_by(SessionMessage.created_at, SessionMessage.id)
        rows = list((await db.scalars(query.limit(limit))).all())
    else:
        query = query.order_by(
            SessionMessage.created_at.desc(), SessionMessage.id.desc()
        )
        rows = list(reversed((await db.scalars(query.limit(limit))).all()))

    return [MessageResponse.model_validate(row) for row in rows]


async def send_message(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
    payload: MessageCreate,
) -> MessageResponse:
    """Add one message and tell the other party, if they are not already told.

    Closed sessions are refused here rather than hidden in the client. A
    session that was cancelled or that nobody attended is not a conversation: it
    has no place and no time to agree, which is the whole reason the thread
    exists. Completed sessions stay open, because the follow-up question after a
    session is the same two people and the same topic.

    The notification is written only when the recipient has no unread message
    from this session. Without that check every "ok" would add a bell row and the
    inbox would become the chat it is supposed to point at.
    """
    session = await _load_session_for_party(db, user, session_id)
    if session.status in {SessionStatus.CANCELLED, SessionStatus.NO_SHOW}:
        raise ConflictProblem("That session is closed, so messages are closed.")

    recipient_id = session.tutor_id if user.id == session.tutee_id else session.tutee_id

    # Counted before this message is added, so the answer is "did the recipient
    # already have something waiting from me".
    already_waiting = await db.scalar(
        select(func.count())
        .select_from(SessionMessage)
        .where(
            SessionMessage.session_id == session.id,
            SessionMessage.sender_id != recipient_id,
            SessionMessage.read_at.is_(None),
        )
    )

    message = SessionMessage(session=session, sender=user, body=payload.body)
    db.add(message)
    await db.flush()

    if not already_waiting:
        await notification_service.message_received(
            db,
            recipient_id=recipient_id,
            sender=user,
            preview=_preview(payload.body),
            session_id=session.public_id,
        )

    await db.commit()
    return MessageResponse.model_validate(message)


async def mark_read(
    db: AsyncSession,
    user: User,
    session_id: uuid.UUID,
) -> MessagesReadResponse:
    """Clear the caller's unread messages in this thread.

    Only rows the other person wrote are touched: marking one's own message read
    would clear the badge on the other person's phone, and the read timestamp is
    evidence of who has seen what. Idempotent, because the screen calls this on
    open and again after every poll that brought something in.
    """
    session = await _load_session_for_party(db, user, session_id)
    result = await db.execute(
        update(SessionMessage)
        .where(
            SessionMessage.session_id == session.id,
            SessionMessage.sender_id != user.id,
            SessionMessage.read_at.is_(None),
        )
        .values(read_at=_utc(datetime.now(UTC)))
        .execution_options(synchronize_session=False)
    )
    await db.commit()
    return MessagesReadResponse(marked=result.rowcount or 0)


async def _load_anchor(
    db: AsyncSession,
    session: Session,
    message_id: uuid.UUID,
) -> SessionMessage:
    """The client's cursor, refusing one that belongs to another thread.

    Scoped to the session rather than looked up globally: a message id from a
    conversation the caller is not part of must not become a valid cursor here,
    even though it would reveal nothing by itself.
    """
    anchor = await db.scalar(
        select(SessionMessage).where(
            SessionMessage.public_id == message_id,
            SessionMessage.session_id == session.id,
        )
    )
    if anchor is None:
        raise NotFoundProblem("That message is not part of this session.")
    return anchor


def _preview(body: str) -> str:
    """The first line of a message, safe to put in a notification body.

    Newlines collapse because a notification is one line; a message that began
    with a blank line would otherwise produce a body that reads as empty.
    """
    collapsed = " ".join(body.split())
    if len(collapsed) <= PREVIEW_LENGTH:
        return collapsed
    return collapsed[: PREVIEW_LENGTH - 3].rstrip() + "..."

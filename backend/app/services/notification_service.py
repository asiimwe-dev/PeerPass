"""In-app notifications and device registration.

Notifications are written in the caller's transaction, never committed here.
That is the whole design: a message announcing a session must not survive the
rollback of the session it describes, and a caller that had to remember to pair
two commits would eventually forget. Every function below adds rows and flushes;
the service that owns the action still owns the commit.

Push is not sent from this module. The in-app row is the durable record and the
only thing the beta reads; a delivery channel can be added behind it without
changing a single call site.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundProblem
from app.models.enums import NotificationType
from app.models.notification import DeviceToken, Notification
from app.models.user import User
from app.schemas.common import PageParams
from app.schemas.notification import (
    DeviceRegistrationRequest,
    DeviceResponse,
    NotificationPage,
    NotificationResponse,
)


async def notify(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    type: NotificationType,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
    dedupe_key: str | None = None,
) -> Notification | None:
    """Add one notification, unless it announces an event already announced.

    A `dedupe_key` makes the write idempotent: a retried request, a reminder job
    that runs twice, or two workers racing on the same event all leave one row.
    The pre-read covers the ordinary case and the unique constraint covers the
    race, which is why the insert runs inside a savepoint -- losing the race has
    to cost nothing rather than poisoning the caller's transaction.

    Returns the row, or None when the key had already been used. Callers that do
    not care about the result can ignore it.
    """
    if dedupe_key is not None:
        existing = await db.scalar(
            select(Notification.id).where(
                Notification.user_id == user_id,
                Notification.dedupe_key == dedupe_key,
            )
        )
        if existing is not None:
            return None

    notification = Notification(
        user_id=user_id,
        type=type,
        title=title,
        body=body,
        data=data,
        dedupe_key=dedupe_key,
    )

    if dedupe_key is None:
        db.add(notification)
        await db.flush()
        return notification

    try:
        async with db.begin_nested():
            db.add(notification)
            await db.flush()
    except IntegrityError:
        # The savepoint restored the session to the state before this insert,
        # so the duplicate object is no longer pending and the caller's
        # transaction is still usable.
        return None
    return notification


def _display_name(user: User | None, fallback: str) -> str:
    """A name safe to put in a sentence.

    `full_name` is nullable because an account exists before onboarding finishes,
    and a deleted account is a tombstone whose name has been scrubbed. Both cases
    are shown to the other party, who cannot correct them, so the model's
    `display_name` decides the words: the email for an unfinished profile, and
    "Deleted user" for a tombstone. A fallback is still needed for the template
    paths that have no user row at all.
    """
    if user is None:
        return fallback
    name = user.display_name.strip()
    return name or fallback


async def request_received(
    db: AsyncSession,
    *,
    tutor_id: uuid.UUID,
    tutee: User | None,
    unit_code: str,
    topic: str,
    request_id: uuid.UUID,
) -> None:
    """Tell the chosen tutor that a student is waiting on their answer."""
    await notify(
        db,
        tutor_id,
        type=NotificationType.REQUEST_RECEIVED,
        title="New tutoring request",
        body=f"{_display_name(tutee, 'A student')} needs help with {topic} in "
        f"{unit_code}.",
        data={"kind": "help_request", "request_id": str(request_id)},
        dedupe_key=f"request-received:{request_id}",
    )


async def request_accepted(
    db: AsyncSession,
    *,
    tutee_id: uuid.UUID,
    tutor: User | None,
    topic: str,
    session_id: uuid.UUID,
) -> None:
    """Tell the student their chosen tutor confirmed and a session exists."""
    name = _display_name(tutor, "Your tutor")
    await notify(
        db,
        tutee_id,
        type=NotificationType.REQUEST_ACCEPTED,
        title="Session booked",
        body=f"{name} accepted your request. Next up: {topic}.",
        data={"kind": "session", "session_id": str(session_id)},
        dedupe_key=f"request-accepted:{session_id}",
    )


async def request_declined(
    db: AsyncSession,
    *,
    tutee_id: uuid.UUID,
    tutor: User | None,
    topic: str,
    request_id: uuid.UUID,
) -> None:
    """Tell the student their chosen tutor said no, without inventing a reason."""
    await notify(
        db,
        tutee_id,
        type=NotificationType.REQUEST_DECLINED,
        title="Tutor unavailable",
        body=f"{_display_name(tutor, 'That tutor')} cannot take {topic} right "
        "now. Choose someone else when you are ready.",
        data={"kind": "help_request", "request_id": str(request_id)},
        dedupe_key=f"request-declined:{request_id}",
    )


async def session_started(
    db: AsyncSession,
    *,
    recipient_id: uuid.UUID,
    checked_in: User | None,
    topic: str,
    session_id: uuid.UUID,
) -> None:
    """Tell the party who was already waiting that both are now present."""
    await notify(
        db,
        recipient_id,
        type=NotificationType.SESSION_STARTED,
        title="Session started",
        body=f"{_display_name(checked_in, 'The other party')} checked in for "
        f"{topic}. You are both here.",
        data={"kind": "session", "session_id": str(session_id)},
        dedupe_key=f"session-started:{session_id}",
    )


async def session_completed(
    db: AsyncSession,
    *,
    tutee_id: uuid.UUID,
    tutor: User | None,
    topic: str,
    session_id: uuid.UUID,
) -> None:
    """Tell the student the session is done and ask for the rating that closes it."""
    name = _display_name(tutor, "your tutor")
    await notify(
        db,
        tutee_id,
        type=NotificationType.SESSION_COMPLETED,
        title="Session complete",
        body=f"How did {topic} go with {name}? Rate the session to close it out.",
        data={"kind": "session", "session_id": str(session_id)},
        dedupe_key=f"session-completed:{session_id}",
    )


async def session_cancelled(
    db: AsyncSession,
    *,
    recipient_id: uuid.UUID,
    cancelled_by: User | None,
    topic: str,
    reason: str | None,
    session_id: uuid.UUID,
) -> None:
    """Tell the other party a session is off, carrying the reason if one was given."""
    body = f"{_display_name(cancelled_by, 'The other party')} cancelled {topic}." + (
        f" Reason: {reason}" if reason else ""
    )
    await notify(
        db,
        recipient_id,
        type=NotificationType.SESSION_CANCELLED,
        title="Session cancelled",
        body=body,
        data={"kind": "session", "session_id": str(session_id)},
        dedupe_key=f"session-cancelled:{session_id}",
    )


async def rating_received(
    db: AsyncSession,
    *,
    tutor_id: uuid.UUID,
    rater: User | None,
    score: int,
    rating_id: uuid.UUID,
    session_id: uuid.UUID,
) -> None:
    """Tell a tutor they were rated, without repeating the written feedback here."""
    await notify(
        db,
        tutor_id,
        type=NotificationType.RATING_RECEIVED,
        title=f"You were rated {score}/5",
        body=f"{_display_name(rater, 'A student')} rated your last session. "
        "Open it to read what they said.",
        data={
            "kind": "rating",
            "rating_id": str(rating_id),
            "session_id": str(session_id),
        },
        dedupe_key=f"rating-received:{rating_id}",
    )


async def promoted(
    db: AsyncSession,
    *,
    tutor_id: uuid.UUID,
) -> None:
    """Tell a tutor their standing moved to Verified.

    Not deduplicated by key: the point is the transition, and the caller only
    calls this when the standing actually changed. A re-promotion after a
    demotion is a second piece of good news.
    """
    await notify(
        db,
        tutor_id,
        type=NotificationType.PROMOTION,
        title="You are Verified",
        body="Your rating average crossed the Verified bar. Verified tutors "
        "rank first in matching.",
    )


async def list_notifications(
    db: AsyncSession,
    user: User,
    params: PageParams,
) -> NotificationPage:
    """One page of the caller's inbox, newest first.

    Scoped to the caller in the query rather than filtered afterwards. A list
    that fetched and then discarded other people's rows would still have read
    them, and the next endpoint built by copying this one would keep the habit.
    """
    query = (
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
    )
    total = await db.scalar(select(func.count()).select_from(query.subquery())) or 0
    rows = list(
        (await db.scalars(query.offset(params.offset).limit(params.limit))).all()
    )
    return NotificationPage(
        items=[NotificationResponse.model_validate(row) for row in rows],
        total=total,
        limit=params.limit,
        offset=params.offset,
    )


async def unread_count(db: AsyncSession, user: User) -> int:
    """How many rows the caller has not read."""
    return (
        await db.scalar(
            select(func.count())
            .select_from(Notification)
            .where(
                Notification.user_id == user.id,
                Notification.read_at.is_(None),
            )
        )
        or 0
    )


async def mark_read(
    db: AsyncSession,
    user: User,
    notification_id: uuid.UUID,
) -> NotificationResponse:
    """Mark one of the caller's notifications read.

    Idempotent: opening a notification twice is ordinary, and the second tap
    should not report a failure for a row that is already in the state asked
    for. A row belonging to someone else is a 404 rather than a 403, because a
    403 would confirm that the id exists.
    """
    result = await db.execute(
        select(Notification).where(Notification.public_id == notification_id)
    )
    notification = result.scalar_one_or_none()
    if notification is None or notification.user_id != user.id:
        raise NotFoundProblem("That notification could not be found.")

    if notification.read_at is None:
        notification.read_at = datetime.now(UTC)
        await db.commit()
        await db.refresh(notification)
    return NotificationResponse.model_validate(notification)


async def mark_all_read(db: AsyncSession, user: User) -> int:
    """Mark every unread row the caller owns, and say how many changed.

    One statement rather than a read followed by per-row writes in Python. The
    clear is a single fact -- "everything unread of mine is read now" -- so it
    does not need the rows themselves, and loading an inbox of a few hundred
    objects to stamp one column would put them all in memory for no answer the
    server did not already have. `read_at` is one timestamp for the whole batch,
    which is what the row loop did too; only the ordering by row disappeared.
    """
    result = await db.execute(
        update(Notification)
        .where(
            Notification.user_id == user.id,
            Notification.read_at.is_(None),
        )
        .values(read_at=datetime.now(UTC))
    )
    await db.commit()
    return result.rowcount or 0


async def register_device(
    db: AsyncSession,
    user: User,
    payload: DeviceRegistrationRequest,
) -> DeviceResponse:
    """Register a handset, moving an existing token to this account.

    Moving rather than rejecting is deliberate. A shared or resold phone is
    normal in the pilot's audience, and refusing the second account would break
    push for the person actually holding the device. The reverse -- leaving the
    old owner attached -- would deliver one student's notifications to another.
    """
    result = await db.execute(
        select(DeviceToken).where(DeviceToken.token == payload.token)
    )
    device = result.scalar_one_or_none()
    now = datetime.now(UTC)
    if device is None:
        device = DeviceToken(
            user_id=user.id,
            token=payload.token,
            platform=payload.platform,
            last_seen_at=now,
        )
        db.add(device)
    else:
        device.user_id = user.id
        device.platform = payload.platform
        device.last_seen_at = now

    await db.commit()
    await db.refresh(device)
    return DeviceResponse.model_validate(device)


async def remove_device(db: AsyncSession, user: User, token: str) -> None:
    """Forget a handset the caller owns.

    Silently succeeds when the token is unknown or belongs to someone else: this
    is called on sign-out, and a sign-out that fails because the device was
    already cleaned up is a user stuck on a screen. Nothing is deleted unless
    the caller owns it, so the silence does not hand anyone a way to unregister
    another person's phone.
    """
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == token,
            DeviceToken.user_id == user.id,
        )
    )
    device = result.scalar_one_or_none()
    if device is not None:
        await db.delete(device)
        await db.commit()

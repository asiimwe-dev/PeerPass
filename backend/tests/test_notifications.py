"""The in-app inbox and push device registration.

The inbox is the beta's durable notification surface. Push is a channel that can
be absent, so every assertion here is about rows a person can read with Firebase
unconfigured.

Two levels are exercised. The service tests pin the behaviour that is easy to
get wrong -- idempotent writes, one user's page never including another's -- and
the wire tests go through the real router, because the auth guard, the path
ordering, and the status codes exist only there.
"""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from app.models.enums import NotificationType
from app.models.notification import DeviceToken, Notification
from app.models.user import User
from app.schemas.notification import DeviceRegistrationRequest
from app.services import notification_service
from tests.support import bearer, register

TOKEN = "fcm-" + ("a" * 140)


async def _me(env, email: str = "inbox@mak.ac.ug") -> tuple[dict, User]:
    body = await register(env.client, email)
    async with env.session() as session:
        user = await session.scalar(select(User).where(User.email == email))
        assert user is not None
    return body, user


async def _write(
    env,
    user: User,
    *,
    count: int = 1,
    title: str = "New tutoring request",
    type: NotificationType = NotificationType.REQUEST_RECEIVED,
    read: bool = False,
) -> list[uuid.UUID]:
    """Stage inbox rows directly, because the inbox reads state, not creates it."""
    ids: list[uuid.UUID] = []
    async with env.session() as session:
        base = datetime(2026, 11, 3, 9, 0, tzinfo=UTC)
        for index in range(count):
            row = Notification(
                user_id=user.id,
                type=type,
                title=title,
                body="Student Example needs help with graphs in CSC 121.",
                read_at=base if read else None,
                created_at=base + timedelta(minutes=index),
            )
            session.add(row)
            await session.flush()
            ids.append(row.public_id)
        await session.commit()
    return ids


async def test_an_empty_inbox_is_a_page_not_an_error(committed_env):
    """An empty list is a state, and the envelope says so without a special case."""
    body, _user = await _me(committed_env)

    response = await committed_env.client.get("/v1/notifications", headers=bearer(body))

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["items"] == []
    assert payload["total"] == 0
    assert payload["has_more"] is False


async def test_the_inbox_is_newest_first_and_never_includes_someone_else(
    committed_env,
):
    """One account's page, and one page's worth of it.

    The second account is not decoration: a list endpoint that forgot its
    `user_id` filter would pass the ordering half of this test on a single-user
    fixture.
    """
    mine, me = await _me(committed_env, "mine@mak.ac.ug")
    _theirs, other = await _me(committed_env, "theirs@mak.ac.ug")
    staged = await _write(committed_env, me, count=3)
    await _write(committed_env, other, count=1, title="Someone else's request")

    response = await committed_env.client.get("/v1/notifications", headers=bearer(mine))

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["total"] == 3
    assert [item["id"] for item in payload["items"]] == [
        str(staged[2]),
        str(staged[1]),
        str(staged[0]),
    ]

    first = await committed_env.client.get(
        "/v1/notifications?limit=1", headers=bearer(mine)
    )
    assert first.json()["total"] == 3
    assert first.json()["has_more"] is True
    assert len(first.json()["items"]) == 1


async def test_unread_count_reading_one_and_reading_all(committed_env):
    """The badge, the single row, and the bulk clear agree with one another."""
    body, me = await _me(committed_env)
    staged = await _write(committed_env, me, count=2)
    await _write(committed_env, me, count=1, read=True)
    headers = bearer(body)

    count = await committed_env.client.get(
        "/v1/notifications/unread-count", headers=headers
    )
    assert count.status_code == 200, count.text
    assert count.json() == {"count": 2}

    read = await committed_env.client.post(
        f"/v1/notifications/{staged[0]}/read", headers=headers
    )
    assert read.status_code == 200, read.text
    assert read.json()["read_at"] is not None

    # The second tap is ordinary on a phone and must not turn a success into a
    # failure for a row that is already in the state asked for.
    again = await committed_env.client.post(
        f"/v1/notifications/{staged[0]}/read", headers=headers
    )
    assert again.status_code == 200, again.text
    assert again.json()["read_at"] == read.json()["read_at"]

    left = await committed_env.client.get(
        "/v1/notifications/unread-count", headers=headers
    )
    assert left.json() == {"count": 1}

    cleared = await committed_env.client.post(
        "/v1/notifications/read-all", headers=headers
    )
    assert cleared.status_code == 200, cleared.text
    assert cleared.json() == {"marked": 1}

    empty = await committed_env.client.get(
        "/v1/notifications/unread-count", headers=headers
    )
    assert empty.json() == {"count": 0}

    # The bulk clear has to have stamped the rows themselves, not just answered
    # with a count. Checked in the database because the unread count could agree
    # with a response that never wrote anything.
    async with committed_env.session() as session:
        unread = await session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == me.id, Notification.read_at.is_(None))
        )
    assert unread == 0

    # A second clear is a no-op rather than a failure: the button is tappable and
    # an empty badge is not an error.
    again_all = await committed_env.client.post(
        "/v1/notifications/read-all", headers=headers
    )
    assert again_all.status_code == 200, again_all.text
    assert again_all.json() == {"marked": 0}


async def test_another_persons_notification_is_not_found(committed_env):
    """A 404 rather than a 403, because a 403 confirms the id exists."""
    mine, _me_user = await _me(committed_env, "mine@mak.ac.ug")
    _theirs, other = await _me(committed_env, "theirs@mak.ac.ug")
    staged = await _write(committed_env, other, count=1)

    response = await committed_env.client.post(
        f"/v1/notifications/{staged[0]}/read", headers=bearer(mine)
    )

    assert response.status_code == 404, response.text
    assert response.headers["content-type"].startswith("application/problem+json")
    async with committed_env.session() as session:
        row = await session.scalar(
            select(Notification).where(Notification.public_id == staged[0])
        )
        assert row is not None
        assert row.read_at is None

    # Read-all is scoped too: the other account's row is still unread.
    await committed_env.client.post("/v1/notifications/read-all", headers=bearer(mine))
    async with committed_env.session() as session:
        remaining = await session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == other.id, Notification.read_at.is_(None))
        )
    assert remaining == 1


async def test_registering_a_device_moves_it_to_the_account_holding_it(
    committed_env,
):
    """A handset that changes hands must not keep delivering the old owner's mail.

    The token is unique across the table, and the second registration is what
    reassigns it. The response deliberately does not echo the token back.
    """
    first, first_user = await _me(committed_env, "first@mak.ac.ug")
    second, second_user = await _me(committed_env, "second@mak.ac.ug")
    payload = {"token": TOKEN, "platform": "android"}

    created = await committed_env.client.post(
        "/v1/notifications/devices", headers=bearer(first), json=payload
    )
    assert created.status_code == 200, created.text
    assert "token" not in created.json()
    assert created.json()["platform"] == "android"

    moved = await committed_env.client.post(
        "/v1/notifications/devices", headers=bearer(second), json=payload
    )
    assert moved.status_code == 200, moved.text

    async with committed_env.session() as session:
        rows = (
            await session.execute(select(DeviceToken).where(DeviceToken.token == TOKEN))
        ).scalars()
        devices = list(rows)
    assert len(devices) == 1
    assert devices[0].user_id == second_user.id

    # The first account can no longer unregister a device it no longer holds.
    removed = await committed_env.client.delete(
        f"/v1/notifications/devices/{TOKEN}", headers=bearer(first)
    )
    assert removed.status_code == 204, removed.text
    async with committed_env.session() as session:
        still_there = await session.scalar(
            select(func.count())
            .select_from(DeviceToken)
            .where(DeviceToken.token == TOKEN)
        )
    assert still_there == 1

    # The owner can, and deleting twice is a sign-out that cannot get stuck.
    for _attempt in range(2):
        gone = await committed_env.client.delete(
            f"/v1/notifications/devices/{TOKEN}", headers=bearer(second)
        )
        assert gone.status_code == 204, gone.text
    async with committed_env.session() as session:
        left = await session.scalar(
            select(func.count())
            .select_from(DeviceToken)
            .where(DeviceToken.user_id == first_user.id)
        )
    assert left == 0


async def test_every_inbox_route_refuses_an_anonymous_caller(committed_env):
    """No endpoint here is public: an inbox is addressed to one person."""
    calls = [
        ("get", "/v1/notifications", None),
        ("get", "/v1/notifications/unread-count", None),
        ("post", "/v1/notifications/read-all", None),
        ("post", "/v1/notifications/devices", {"token": TOKEN, "platform": "android"}),
        ("delete", f"/v1/notifications/devices/{TOKEN}", None),
    ]
    for method, path, payload in calls:
        response = await committed_env.client.request(method, path, json=payload)
        assert response.status_code == 401, f"{method} {path} -> {response.status_code}"


async def test_a_dedupe_key_makes_a_notification_idempotent(db_session):
    """A retried event leaves one row, and the caller's transaction still works.

    The second insert loses to a unique constraint inside a savepoint. What is
    asserted after it is not decoration: a savepoint that left the failed object
    pending would fail on the next flush, which is exactly the sort of bug a
    "count == 1" assertion alone would miss.
    """
    user = User(
        email="dedupe@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Dedupe Tester",
    )
    db_session.add(user)
    await db_session.flush()

    first = await notification_service.notify(
        db_session,
        user.id,
        type=NotificationType.REQUEST_RECEIVED,
        title="New tutoring request",
        body="A student needs help.",
        dedupe_key="request-received:one",
    )
    second = await notification_service.notify(
        db_session,
        user.id,
        type=NotificationType.REQUEST_RECEIVED,
        title="New tutoring request",
        body="A student needs help.",
        dedupe_key="request-received:one",
    )
    await notification_service.notify(
        db_session,
        user.id,
        type=NotificationType.PROMOTION,
        title="You are Verified",
        body="Your rating average crossed the Verified bar.",
    )
    await db_session.commit()

    assert first is not None
    assert second is None
    total = await db_session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == user.id)
    )
    assert total == 2


async def test_registering_a_device_directly_is_idempotent(db_session):
    """The service half of the token move, without the router in the way."""
    first = User(
        email="device-one@mak.ac.ug",
        password_hash="hashed-password",
        full_name="First Owner",
    )
    second = User(
        email="device-two@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Second Owner",
    )
    db_session.add_all([first, second])
    await db_session.flush()

    payload = DeviceRegistrationRequest(token=TOKEN, platform="android")
    await notification_service.register_device(db_session, first, payload)
    await notification_service.register_device(db_session, second, payload)

    devices = list((await db_session.scalars(select(DeviceToken))).all())
    assert len(devices) == 1
    assert devices[0].user_id == second.id

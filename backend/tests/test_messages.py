"""Session messages over the real router.

The thread is the one place a student and a tutor can agree on details after a
request is accepted, so these tests care about the two failures that would make
it useless rather than merely buggy: someone who is not on the session reading or
writing to it, and the other party never learning that a message arrived.

Everything is exercised through HTTP, including the notification, because a
service-level check would not prove the route, the auth guard, or the query the
inbox actually runs.
"""

import uuid

import pytest
from sqlalchemy import select

from app.models.message import SessionMessage
from app.models.session import Session
from tests.conftest import CommittedEnv
from tests.support import (
    bearer,
    complete_profile,
    first_course_unit,
    register,
    scheduled_session,
    verified_tutor,
)


@pytest.fixture
async def booked(committed_env: CommittedEnv) -> dict:
    course_unit = await first_course_unit(committed_env)
    tutor = await verified_tutor(committed_env, "message.tutor@peerpass.mak.ac.ug")
    student = await register(committed_env.client, "message.student@student.mak.ac.ug")
    await complete_profile(committed_env.client, student, course_unit=course_unit)
    session = await scheduled_session(committed_env, tutor, student, course_unit)
    return {
        "env": committed_env,
        "client": committed_env.client,
        "session": session,
        "session_id": session["id"],
        "tutor": tutor,
        "student": student,
        "course_unit": course_unit,
    }


async def _send(ctx: dict, who: str, body: str):
    return await ctx["client"].post(
        f"/v1/sessions/{ctx['session_id']}/messages",
        headers=bearer(ctx[who]),
        json={"body": body},
    )


async def _read(ctx: dict, who: str, **params) -> list[dict]:
    response = await ctx["client"].get(
        f"/v1/sessions/{ctx['session_id']}/messages",
        headers=bearer(ctx[who]),
        params=params,
    )
    assert response.status_code == 200, response.text
    return response.json()


async def _session(ctx: dict, who: str) -> dict:
    response = await ctx["client"].get(
        f"/v1/sessions/{ctx['session_id']}", headers=bearer(ctx[who])
    )
    assert response.status_code == 200, response.text
    return response.json()


async def _inbox(ctx: dict, who: str) -> list[dict]:
    response = await ctx["client"].get("/v1/notifications", headers=bearer(ctx[who]))
    assert response.status_code == 200, response.text
    return response.json()["items"]


async def test_the_tutor_can_say_where_the_session_is(booked: dict) -> None:
    sent = await _send(booked, "tutor", "Library, second floor, 3pm.")

    assert sent.status_code == 201, sent.text
    assert sent.json()["body"] == "Library, second floor, 3pm."
    assert sent.json()["session_id"] == booked["session_id"]
    assert sent.json()["read_at"] is None
    # The sender is named by the API, never chosen by the client.
    assert (
        sent.json()["sender_id"]
        == (
            await booked["client"].get("/v1/auth/me", headers=bearer(booked["tutor"]))
        ).json()["id"]
    )

    thread = await _read(booked, "student")
    assert [row["body"] for row in thread] == ["Library, second floor, 3pm."]


async def test_a_message_is_trimmed_and_an_empty_one_is_refused(
    booked: dict,
) -> None:
    trimmed = await _send(booked, "tutor", "   Canteen at two   ")
    assert trimmed.status_code == 201, trimmed.text
    assert trimmed.json()["body"] == "Canteen at two"

    empty = await _send(booked, "tutor", "   ")
    assert empty.status_code == 422, empty.text


async def test_a_stranger_cannot_read_or_write_the_thread(booked: dict) -> None:
    other = await register(booked["client"], "message.outsider@student.mak.ac.ug")
    await complete_profile(booked["client"], other, course_unit=booked["course_unit"])

    read = await booked["client"].get(
        f"/v1/sessions/{booked['session_id']}/messages", headers=bearer(other)
    )
    write = await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/messages",
        headers=bearer(other),
        json={"body": "let me in"},
    )

    assert read.status_code == 403, read.text
    assert write.status_code == 403, write.text


async def test_a_message_from_someone_who_is_not_on_the_session_never_lands(
    booked: dict,
) -> None:
    # The write above is refused before it is stored. Proving that matters more
    # than the status code: a rejected request that still inserted would leave a
    # row the other party could read.
    other = await register(booked["client"], "message.injector@student.mak.ac.ug")
    await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/messages",
        headers=bearer(other),
        json={"body": "let me in"},
    )

    assert await _read(booked, "student") == []


async def test_the_thread_reads_oldest_first_and_polls_from_a_cursor(
    booked: dict,
) -> None:
    first = await _send(booked, "tutor", "one")
    second = await _send(booked, "student", "two")
    third = await _send(booked, "tutor", "three")
    assert first.status_code == second.status_code == third.status_code == 201

    thread = await _read(booked, "tutor")
    assert [row["body"] for row in thread] == ["one", "two", "three"]

    # A poll carries the last message the client already has, and gets only what
    # arrived after it -- not the whole thread again.
    after = await _read(booked, "tutor", after=thread[1]["id"])
    assert [row["body"] for row in after] == ["three"]

    nothing_new = await _read(booked, "tutor", after=thread[-1]["id"])
    assert nothing_new == []


async def test_a_cursor_from_another_thread_is_refused(booked: dict) -> None:
    # Other sessions exist for this tutor in other tests; use an id that is
    # definitely not in this thread.
    response = await booked["client"].get(
        f"/v1/sessions/{booked['session_id']}/messages",
        headers=bearer(booked["student"]),
        params={"after": str(uuid.uuid4())},
    )

    assert response.status_code == 404, response.text


async def test_an_unread_message_shows_on_the_session_and_clears_on_read(
    booked: dict,
) -> None:
    await _send(booked, "tutor", "Meet me at the library.")

    student_view = await _session(booked, "student")
    assert student_view["unread_message_count"] == 1
    # The sender is not waiting on themselves.
    assert (await _session(booked, "tutor"))["unread_message_count"] == 0

    read = await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/messages/read",
        headers=bearer(booked["student"]),
    )
    assert read.status_code == 200, read.text
    assert read.json()["marked"] == 1

    assert (await _session(booked, "student"))["unread_message_count"] == 0
    # Reading the other party's message does not mark the reader's own as read
    # for the person waiting on it.
    assert (await _session(booked, "tutor"))["unread_message_count"] == 0

    again = await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/messages/read",
        headers=bearer(booked["student"]),
    )
    assert again.json()["marked"] == 0


async def test_sending_one_own_message_does_not_count_as_unread(
    booked: dict,
) -> None:
    await _send(booked, "tutor", "I wrote this one.")

    assert (await _session(booked, "tutor"))["unread_message_count"] == 0


async def test_the_recipient_is_told_once_per_quiet_stretch(booked: dict) -> None:
    await _send(booked, "tutor", "Library, second floor.")
    await _send(booked, "tutor", "Bring the past papers.")

    inbox = await _inbox(booked, "student")
    message_rows = [row for row in inbox if row["type"] == "message_received"]
    assert len(message_rows) == 1, (
        "a bell row per line turns the inbox into the chat it points at"
    )
    assert message_rows[0]["data"]["session_id"] == booked["session_id"]
    assert "Library, second floor." in message_rows[0]["body"]

    # Reading the thread ends the quiet stretch: the next message is news again.
    await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/messages/read",
        headers=bearer(booked["student"]),
    )
    await _send(booked, "tutor", "Third floor actually.")

    inbox = await _inbox(booked, "student")
    message_rows = [row for row in inbox if row["type"] == "message_received"]
    assert len(message_rows) == 2


async def test_a_completed_session_still_takes_messages(booked: dict) -> None:
    # The follow-up question after a session is the same two people and the same
    # topic. What is closed is a session that never happened.
    await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/check-in",
        headers=bearer(booked["tutor"]),
    )
    await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/check-in",
        headers=bearer(booked["student"]),
    )
    await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/finish",
        headers=bearer(booked["tutor"]),
    )
    finished = await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/finish",
        headers=bearer(booked["student"]),
    )
    assert finished.json()["status"] == "completed"

    sent = await _send(booked, "student", "Thanks, that helped.")

    assert sent.status_code == 201, sent.text


async def test_a_cancelled_session_closes_the_thread(booked: dict) -> None:
    cancelled = await booked["client"].post(
        f"/v1/sessions/{booked['session_id']}/transition",
        headers=bearer(booked["tutor"]),
        json={"status": "cancelled", "cancellation_reason": "Tutor is unwell"},
    )
    assert cancelled.status_code == 200, cancelled.text

    sent = await _send(booked, "student", "Are we still on?")

    assert sent.status_code == 409, sent.text


async def test_a_message_that_was_never_stored_does_not_reach_the_thread(
    booked: dict,
) -> None:
    # The database bound is the last line, not the schema's. A body at the limit
    # is accepted; one past it is refused by the request schema before it can
    # reach the table.
    allowed = await _send(booked, "tutor", "a" * 2000)
    assert allowed.status_code == 201, allowed.text

    too_long = await _send(booked, "tutor", "a" * 2001)
    assert too_long.status_code == 422, too_long.text

    rows = await _read(booked, "student")
    assert [len(row["body"]) for row in rows] == [2000]


async def test_deleting_the_session_takes_its_messages(booked: dict) -> None:
    # A cascade rather than orphan rows, checked directly because no endpoint
    # deletes a session and the only thing that would exercise it is a data fix.
    await _send(booked, "tutor", "hello")
    async with booked["env"].session() as session:
        row = await session.scalar(
            select(Session).where(Session.public_id == uuid.UUID(booked["session_id"]))
        )
        assert row is not None
        await session.delete(row)
        await session.commit()

        remaining = await session.scalar(
            select(SessionMessage).where(SessionMessage.session_id == row.id)
        )
        assert remaining is None


async def test_the_thread_is_not_readable_without_a_token(booked: dict) -> None:
    response = await booked["client"].get(
        f"/v1/sessions/{booked['session_id']}/messages"
    )
    assert response.status_code == 401, response.text

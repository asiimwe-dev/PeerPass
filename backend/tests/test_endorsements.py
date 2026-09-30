"""Unit-scoped endorsements.

An endorsement is a claim about *coverage* rather than a second opinion about a
tutor's manner, so almost everything tested here is about it not being the
rating under another name: it is separate, it is scoped to the session's own
course unit, it is optional, and a corrected submission replaces it rather than
piling on top of it.

The last third of the file goes through the real router. Calling the service
directly proves the rules and nothing about the route, the auth guard, or the
response shape, and a route wired to the wrong dependency passes every one of
those tests.
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

import pytest
from pydantic import ValidationError
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError

from app.core.exceptions import ValidationProblem
from app.models.course_unit import CourseUnit, Subject, University
from app.models.endorsement import UnitEndorsement
from app.models.enums import SessionStatus, UserRole
from app.models.session import Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User, set_roles
from app.schemas.rating import MAX_ENDORSEMENTS_PER_RATING, RatingCreate
from app.services import rating_service

GOOD_PASSWORD = "correct horse battery staple"


async def _seed(db_session, *, unit_code: str = "CSC 121") -> tuple:
    """A completed session for one course unit, plus a second unit to try instead.

    The second unit exists so "endorsing the wrong unit" can be tested against a
    real row rather than against a random UUID that would fail the lookup for a
    different reason and prove nothing about the rule.
    """
    university = University(name="Makerere University")
    subject = Subject(name="Computer Science")
    course_unit = CourseUnit(
        code=unit_code,
        name="Algorithms",
        subject=subject,
        university=university,
    )
    other_unit = CourseUnit(
        code="MTH 221",
        name="Linear Algebra",
        subject=subject,
        university=university,
    )
    student = User(
        email="endorse-student@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Endorsing Student",
    )
    tutor = User(
        email="endorse-tutor@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Endorsed Tutor",
    )
    db_session.add_all([university, subject, course_unit, other_unit, student, tutor])
    await db_session.flush()
    session = Session(
        tutee_id=student.id,
        tutor_id=tutor.id,
        course_unit_id=course_unit.id,
        topic="Quick sort",
        status=SessionStatus.COMPLETED,
        started_at=datetime.now(UTC),
        ended_at=datetime.now(UTC),
        duration_minutes=60,
    )
    db_session.add(session)
    await db_session.flush()
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})
    return student, tutor, session, course_unit, other_unit


async def _endorsement_rows(db_session, session: Session) -> list[UnitEndorsement]:
    result = await db_session.execute(
        select(UnitEndorsement).where(UnitEndorsement.session_id == session.id)
    )
    return list(result.scalars())


# --- writing ----------------------------------------------------------------


async def test_endorsing_the_session_course_unit_creates_the_endorsement(
    db_session,
) -> None:
    """The one unit a session can honestly vouch for, stored."""
    student, tutor, session, course_unit, _other = await _seed(db_session)

    rating = await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )

    assert rating.score == 5
    rows = await _endorsement_rows(db_session, session)
    assert len(rows) == 1
    endorsement = rows[0]
    assert endorsement.course_unit_id == course_unit.id
    # Both parties come from the session, never from the body.
    assert endorsement.rater_id == student.id
    assert endorsement.ratee_id == tutor.id


async def test_a_rating_may_carry_no_endorsement(db_session) -> None:
    """Endorsing is optional, and the default has to be "no endorsement".

    A student who was shown up to by a tutor should be able to say so with a
    score alone. If omitting the field were an error, or defaulted to something
    other than nothing, the only way to get through the form would be to
    endorse.
    """
    student, _tutor, session, _course_unit, _other = await _seed(db_session)

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=1),
    )

    assert await _endorsement_rows(db_session, session) == []


async def test_endorsing_a_unit_the_session_is_not_about_is_rejected(
    db_session,
) -> None:
    """A session is booked for one unit, so it can only vouch for that one.

    The rejection names the field, so a client can put the message next to the
    input rather than showing a bare "something went wrong".
    """
    student, _tutor, session, _course_unit, other_unit = await _seed(db_session)

    with pytest.raises(ValidationProblem) as raised:
        await rating_service.submit_rating(
            db_session,
            student,
            session.public_id,
            RatingCreate(score=5, endorsed_course_unit_ids=[other_unit.public_id]),
        )

    assert "endorsed_course_unit_ids" in raised.value.errors
    assert str(other_unit.public_id) in raised.value.errors["endorsed_course_unit_ids"]
    # Nothing was written: the rejection happens before any write, so a rating
    # cannot survive without the endorsement that was asked for.
    assert await _endorsement_rows(db_session, session) == []


async def test_endorsing_a_course_unit_that_does_not_exist_is_rejected(
    db_session,
) -> None:
    """An id that resolves to no unit is refused with the same field-level error.

    Fixed rather than random so a failure cannot be mistaken for the
    cross-unit rule being exercised by accident.
    """
    student, _tutor, session, _course_unit, _other = await _seed(db_session)
    unknown = uuid.UUID(int=0)

    with pytest.raises(ValidationProblem) as raised:
        await rating_service.submit_rating(
            db_session,
            student,
            session.public_id,
            RatingCreate(score=5, endorsed_course_unit_ids=[unknown]),
        )

    assert "endorsed_course_unit_ids" in raised.value.errors
    assert await _endorsement_rows(db_session, session) == []


# --- replacing, not accumulating ---------------------------------------------


async def test_rerating_replaces_the_endorsements_rather_than_accumulating(
    db_session,
) -> None:
    """Re-submitting the same unit leaves exactly one claim, not two.

    The aggregate would otherwise count a single session twice, and the unique
    key exists precisely so this cannot be reached by accident -- but the service
    replacing the row is what makes the retry safe in the first place.
    """
    student, _tutor, session, course_unit, _other = await _seed(db_session)

    for _attempt in range(2):
        await rating_service.submit_rating(
            db_session,
            student,
            session.public_id,
            RatingCreate(score=4, endorsed_course_unit_ids=[course_unit.public_id]),
        )

    rows = await _endorsement_rows(db_session, session)
    assert len(rows) == 1


async def test_rerating_with_an_empty_list_withdraws_the_endorsement(
    db_session,
) -> None:
    """Removing a unit from a corrected submission makes the claim go away.

    The second submission is the rater correcting the first. If it merged rather
    than replaced, a withdrawn claim would stay in the per-unit aggregate
    forever with no way to remove it -- which would be worse than having no
    endorsement at all.
    """
    student, _tutor, session, course_unit, _other = await _seed(db_session)

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )
    assert len(await _endorsement_rows(db_session, session)) == 1

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[]),
    )

    assert await _endorsement_rows(db_session, session) == []


async def test_a_withdrawn_endorsement_can_be_made_again(db_session) -> None:
    """Withdrawing is not one-way, and the re-added row is a fresh one.

    Asserted on the public id changing, so a withdrawal that silently no-opped
    would fail here even if a row happened to still exist.
    """
    student, _tutor, session, course_unit, _other = await _seed(db_session)

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )
    first = (await _endorsement_rows(db_session, session))[0].public_id

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[]),
    )
    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )

    rows = await _endorsement_rows(db_session, session)
    assert len(rows) == 1
    assert rows[0].public_id != first


async def test_only_the_raters_own_endorsements_are_replaced(db_session) -> None:
    """The other party's endorsements on the same session survive a re-submission.

    Both parties may rate a session, so "delete everything for this session" is
    the wrong replacement scope -- it would let one party withdraw the other's
    claim.
    """
    student, tutor, session, course_unit, _other = await _seed(db_session)

    # Seed the tutor's endorsement directly: the service always rates the other
    # party, so a tutor endorsing their own session needs another rater and is
    # not reachable from here.
    db_session.add(
        UnitEndorsement(
            session_id=session.id,
            rater_id=tutor.id,
            ratee_id=student.id,
            course_unit_id=course_unit.id,
        )
    )
    await db_session.flush()

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=4, endorsed_course_unit_ids=[]),
    )

    rows = await _endorsement_rows(db_session, session)
    assert len(rows) == 1
    assert rows[0].rater_id == tutor.id


# --- the schema's own guards ------------------------------------------------


def test_duplicate_endorsed_units_are_refused_by_the_schema() -> None:
    """A unit listed twice is not a stronger claim, so it is refused up front.

    Without this the duplicate would reach the unique constraint and surface as
    an unhandled integrity error for something the client can be told plainly.
    """
    unit = uuid.uuid4()

    with pytest.raises(ValidationError, match="duplicates"):
        RatingCreate(score=4, endorsed_course_unit_ids=[unit, unit])


def test_the_endorsement_list_is_bounded() -> None:
    """A payload naming an absurd number of units is refused before any lookup.

    Fixed ids rather than random ones: the assertion is about the count, and a
    random source would only add a way for this test to be flaky.
    """
    too_many = [
        uuid.UUID(int=index) for index in range(MAX_ENDORSEMENTS_PER_RATING + 1)
    ]

    with pytest.raises(ValidationError):
        RatingCreate(score=4, endorsed_course_unit_ids=too_many)


async def test_the_database_refuses_a_party_endorsing_themselves(db_session) -> None:
    """The self-endorsement check holds without the service having to hold it.

    The service can never produce this -- rater and ratee always come from the
    session's two distinct parties -- so the constraint is the only thing standing
    between a future write path and a tutor vouching for themselves. Asserted
    against the database so a refactor of the service cannot quietly remove the
    only check.
    """
    student, _tutor, session, course_unit, _other = await _seed(db_session)
    db_session.add(
        UnitEndorsement(
            session_id=session.id,
            rater_id=student.id,
            ratee_id=student.id,
            course_unit_id=course_unit.id,
        )
    )

    with pytest.raises(IntegrityError):
        await db_session.flush()
    await db_session.rollback()


async def test_the_database_refuses_the_same_unit_endorsed_twice(db_session) -> None:
    """The unique key, tested on its own rather than through the service."""
    student, _tutor, session, course_unit, _other = await _seed(db_session)
    for _ in range(2):
        db_session.add(
            UnitEndorsement(
                session_id=session.id,
                rater_id=student.id,
                ratee_id=_tutor.id,
                course_unit_id=course_unit.id,
            )
        )

    with pytest.raises(IntegrityError):
        await db_session.flush()
    await db_session.rollback()


async def test_an_endorsement_does_not_outlive_its_session(db_session) -> None:
    """The cascade on `session_id` actually fires.

    SQLite enforces no foreign keys unless asked to, so this is the assertion
    that distinguishes "the column says CASCADE" from "the rows go away".
    """
    student, _tutor, session, course_unit, _other = await _seed(db_session)
    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )
    assert len(await _endorsement_rows(db_session, session)) == 1
    # Read before the delete: a bulk delete expires the ORM instance, so touching
    # `session.id` afterwards would be reading a row that is no longer there.
    session_pk = session.id

    await db_session.execute(delete(Session).where(Session.id == session_pk))
    await db_session.flush()

    remaining = await db_session.scalar(
        select(func.count())
        .select_from(UnitEndorsement)
        .where(UnitEndorsement.session_id == session_pk)
    )
    assert remaining == 0


# --- the aggregate ----------------------------------------------------------


async def test_the_per_unit_aggregate_counts_only_endorsed_units(db_session) -> None:
    """Units with no endorsement are absent rather than present with a zero.

    A zero would read as "endorsed here and rated badly". Absence is not a claim
    that the tutor is weak in a unit; it is the absence of a claim, and the two
    are not the same information.
    """
    student, tutor, session, course_unit, _other = await _seed(db_session)
    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )

    summary = await rating_service.get_tutor_rating_summary(db_session, tutor)

    assert [
        (row.course_unit_id, row.endorsement_count) for row in summary.per_unit
    ] == [(course_unit.public_id, 1)]
    # A rating with no endorsement still counts towards the rating total and
    # leaves no unit entry behind.
    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[]),
    )
    summary = await rating_service.get_tutor_rating_summary(db_session, tutor)
    assert summary.rating_count == 1
    assert summary.per_unit == []


async def test_the_aggregate_counts_each_session_once_across_raters(db_session) -> None:
    """Two students endorsing the same tutor for the same unit is a count of two.

    Stated because it is the number matching will eventually weight, and an
    aggregate that collapsed distinct raters into one would understate a tutor
    with a broad following.
    """
    student, tutor, session, course_unit, _other = await _seed(db_session)
    second_student = User(
        email="endorse-student-two@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Second Student",
    )
    db_session.add(second_student)
    await db_session.flush()
    second_session = Session(
        tutee_id=second_student.id,
        tutor_id=tutor.id,
        course_unit_id=course_unit.id,
        topic="Merge sort",
        status=SessionStatus.COMPLETED,
        started_at=datetime.now(UTC),
        ended_at=datetime.now(UTC),
        duration_minutes=60,
    )
    db_session.add(second_session)
    await db_session.flush()

    for rater, rated in ((student, session), (second_student, second_session)):
        await rating_service.submit_rating(
            db_session,
            rater,
            rated.public_id,
            RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
        )

    summary = await rating_service.get_tutor_rating_summary(db_session, tutor)
    assert len(summary.per_unit) == 1
    assert summary.per_unit[0].endorsement_count == 2


async def test_the_aggregate_reports_public_ids_only(db_session) -> None:
    """The entry names the unit the way a client can address it.

    A leaked primary key is a leaked row count, and this is the one aggregate
    whose rows are grouped rather than read off a model, so it is the one place
    the rule has no `from_attributes` alias to enforce it for us.
    """
    student, tutor, session, course_unit, _other = await _seed(db_session)
    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )

    summary = await rating_service.get_tutor_rating_summary(db_session, tutor)

    assert summary.per_unit[0].course_unit_id == course_unit.public_id
    assert summary.per_unit[0].course_unit_id != course_unit.id


async def test_the_aggregate_is_ordered_and_stable(db_session) -> None:
    """Most endorsed first.

    Asserted because the ordering is part of what the field promises, and
    because an unordered aggregate is a flaky one: the same rows in a different
    order on every call would make any client diffing two summaries meaningless.
    The counts and the codes disagree on purpose -- the most-endorsed unit is the
    one whose code sorts last -- so dropping the count ordering fails here rather
    than coinciding with the order the query plan happens to produce.

    The course-code tiebreak that follows the count is not asserted, and cannot
    be: with equal counts the group's row order is whatever the plan chooses, and
    it matched the code order on both PostgreSQL and SQLite even with the
    tiebreak removed. It is there for determinism across plans and backends, not
    because a test can pin it down.
    """
    student, tutor, _seeded_session, course_unit, other_unit = await _seed(db_session)
    third_unit = CourseUnit(
        code="PHY 111",
        name="Mechanics",
        subject=course_unit.subject,
        university=course_unit.university,
    )
    second_student = User(
        email="order-second-student@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Order Second Student",
    )
    db_session.add_all([third_unit, second_student])
    await db_session.flush()

    rated: list[tuple[User, CourseUnit]] = [
        # `other_unit` is "MTH 221" -- last by code, first by count.
        (student, other_unit),
        (second_student, other_unit),
        (student, course_unit),
        (student, third_unit),
    ]
    for rater, unit in rated:
        rated_session = Session(
            tutee_id=rater.id,
            tutor_id=tutor.id,
            course_unit_id=unit.id,
            topic=f"Work on {unit.code}",
            status=SessionStatus.COMPLETED,
            started_at=datetime.now(UTC),
            ended_at=datetime.now(UTC),
            duration_minutes=60,
        )
        db_session.add(rated_session)
        await db_session.flush()
        await rating_service.submit_rating(
            db_session,
            rater,
            rated_session.public_id,
            RatingCreate(score=5, endorsed_course_unit_ids=[unit.public_id]),
        )

    summary = await rating_service.get_tutor_rating_summary(db_session, tutor)

    assert [
        (row.course_unit_id, row.endorsement_count) for row in summary.per_unit
    ] == [
        (other_unit.public_id, 2),
        (course_unit.public_id, 1),
        (third_unit.public_id, 1),
    ]


async def test_the_aggregate_is_empty_for_a_tutor_with_no_endorsements(
    db_session,
) -> None:
    """No endorsements is an empty list, not a 404 and not a null."""
    student, tutor, session, _course_unit, _other = await _seed(db_session)

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=2),
    )

    summary = await rating_service.get_tutor_rating_summary(db_session, tutor)

    assert summary.rating_count == 1
    assert summary.per_unit == []


# --- the wire contract ------------------------------------------------------
#
# `_register` and `_bearer` are the helpers from `test_ratings.py`, repeated
# rather than imported so a failure in either file points at the file that owns
# the case. Everything below goes through the real router with a real access
# token: the tests above prove the rules, and none of them proves the route, the
# auth guard, or the response shape.


async def _register(client, email: str) -> dict:
    response = await client.post(
        "/v1/auth/register", json={"email": email, "password": GOOD_PASSWORD}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _bearer(body: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {body['tokens']['access_token']}"}


async def _registered_party(client, db_session, email: str) -> tuple:
    """Register a real account and return its body alongside the `User` row.

    Registering through the router is the only way to get a row carrying a
    usable password hash, so the seeded session is re-pointed at the registered
    accounts rather than the accounts being forged around seeded users.
    """
    body = await _register(client, email)
    user = await db_session.scalar(select(User).where(User.email == email))
    assert user is not None
    return body, user


async def _seed_for_the_wire(client, db_session, *, tag: str) -> tuple:
    """A completed session whose parties both hold real access tokens."""
    university = University(name="Makerere University")
    subject = Subject(name="Computer Science")
    course_unit = CourseUnit(
        code=f"CSC {tag}",
        name="Algorithms",
        subject=subject,
        university=university,
    )
    db_session.add_all([university, subject, course_unit])
    await db_session.flush()

    student_body, student = await _registered_party(
        client, db_session, f"wire-student-{tag}@mak.ac.ug"
    )
    tutor_body, tutor = await _registered_party(
        client, db_session, f"wire-tutor-{tag}@mak.ac.ug"
    )
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})
    session = Session(
        tutee_id=student.id,
        tutor_id=tutor.id,
        course_unit_id=course_unit.id,
        topic="Quick sort",
        status=SessionStatus.COMPLETED,
        started_at=datetime.now(UTC),
        ended_at=datetime.now(UTC),
        duration_minutes=60,
    )
    db_session.add(session)
    await db_session.flush()
    await db_session.commit()
    return student_body, tutor_body, session, course_unit


async def test_endorsement_through_the_router_reaches_the_summary(
    client, db_session
) -> None:
    """A real POST with endorsements, then a real GET that reports them.

    The response body is not where the aggregate lives, so this asserts on
    `GET /v1/ratings/me` rather than on the 201: a route that accepted the field
    and dropped it on the floor would otherwise pass.
    """
    student_body, tutor_body, session, course_unit = await _seed_for_the_wire(
        client, db_session, tag="121"
    )

    response = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 5, "endorsed_course_unit_ids": [str(course_unit.public_id)]},
        headers=_bearer(student_body),
    )

    assert response.status_code == 201, response.text
    assert response.json()["score"] == 5

    summary = await client.get("/v1/ratings/me", headers=_bearer(tutor_body))

    assert summary.status_code == 200, summary.text
    payload = summary.json()
    assert payload["per_unit"] == [
        {"course_unit_id": str(course_unit.public_id), "endorsement_count": 1}
    ]


async def test_endorsing_a_foreign_unit_through_the_router_is_a_422(
    client, db_session
) -> None:
    """The rejection reaches the client as a field-level 422, not a 500.

    Goes through the router because the point is what the client receives: a
    `ValidationProblem` rendered as problem details with `errors` beside the
    input. A service that raised the same exception but reached an unhandled
    handler would still pass every service-level test above.
    """
    _seed_body, _tutor_body, session, _seed_unit = await _seed_for_the_wire(
        client, db_session, tag="221"
    )
    elsewhere = University(name="Ndejje University")
    subject = Subject(name="Maths")
    foreign_unit = CourseUnit(
        code="MTH 221",
        name="Linear Algebra",
        subject=subject,
        university=elsewhere,
    )
    db_session.add_all([elsewhere, subject, foreign_unit])
    await db_session.flush()
    await db_session.commit()

    student_body, adopter = await _registered_party(
        client, db_session, "wire-outsider-221@mak.ac.ug"
    )
    # Adopt the new registration as the session's tutee so the token belongs to a
    # party of it; otherwise the request would fail authorisation and never reach
    # the endorsement rule.
    session.tutee_id = adopter.id
    await db_session.commit()

    response = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 4, "endorsed_course_unit_ids": [str(foreign_unit.public_id)]},
        headers=_bearer(student_body),
    )

    assert response.status_code == 422, response.text
    problem = response.json()
    assert problem["code"] == "validation_failed"
    assert str(foreign_unit.public_id) in problem["errors"]["endorsed_course_unit_ids"]

    # A refused endorsement must leave no trace, or the student is left with a
    # rating they did not submit.
    rows = await _endorsement_rows(db_session, session)
    assert rows == []


async def test_withdrawing_an_endorsement_through_the_router(
    client, db_session
) -> None:
    """The correction path end to end: endorse, then submit an empty list.

    This is the one route whose bug would not show up on the create path -- a
    service that merged on the second submission would answer 201 and leave the
    count at one, so only the GET after the second POST tells the truth.
    """
    student_body, tutor_body, session, course_unit = await _seed_for_the_wire(
        client, db_session, tag="321"
    )

    first = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 5, "endorsed_course_unit_ids": [str(course_unit.public_id)]},
        headers=_bearer(student_body),
    )
    assert first.status_code == 201, first.text

    second = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 5, "endorsed_course_unit_ids": []},
        headers=_bearer(student_body),
    )
    assert second.status_code == 201, second.text

    summary = await client.get("/v1/ratings/me", headers=_bearer(tutor_body))
    assert summary.status_code == 200, summary.text
    payload = summary.json()
    # The rating still stands; only the endorsement was withdrawn.
    assert payload["rating_count"] == 1
    assert payload["per_unit"] == []


async def test_a_duplicate_endorsed_unit_through_the_router_is_a_422(
    client, db_session
) -> None:
    """Refused at the edge with a field message rather than as a 500."""
    student_body, _tutor_body, session, course_unit = await _seed_for_the_wire(
        client, db_session, tag="421"
    )

    response = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={
            "score": 4,
            "endorsed_course_unit_ids": [
                str(course_unit.public_id),
                str(course_unit.public_id),
            ],
        },
        headers=_bearer(student_body),
    )

    assert response.status_code == 422, response.text
    assert await _endorsement_rows(db_session, session) == []


# --- standing is a tutor's, and only a tutor's ------------------------------
#
# Both parties can rate a completed session, so `ratee_id` is whichever of them
# did not press the button. Standing, the running average, and the per-unit
# aggregate all describe a *tutor*. These tests pin the case where the tutee
# rates their tutor, which is the direction that would otherwise mint a
# `TutorProfile` for a student.


async def test_a_tutee_rating_their_tutor_creates_no_tutor_profile(
    db_session,
) -> None:
    """The score is recorded; the student is not promoted into a standing."""
    student, tutor, session, course_unit, _other = await _seed(db_session)

    rating = await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )

    # The rating is real feedback about the session and is kept.
    assert rating.score == 5
    assert rating.ratee_id == tutor.public_id

    # The tutee is the rater, so no standing is theirs to move.
    profile = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == student.id)
    )
    assert profile is None, "a tutee was given a tutor profile by rating"


async def test_a_tutee_rating_does_not_credit_the_students_counters(
    db_session,
) -> None:
    student, _tutor, session, course_unit, _other = await _seed(db_session)

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, endorsed_course_unit_ids=[course_unit.public_id]),
    )

    profile = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == student.id)
    )
    assert profile is None
    assert await _endorsement_rows(db_session, session) is not None


async def test_a_tutor_rating_their_tutee_creates_no_tutor_profile(
    db_session,
) -> None:
    """The reverse direction: a tutor rating a student must not promote anyone."""
    student, tutor, session, _course_unit, _other = await _seed(db_session)

    await rating_service.submit_rating(
        db_session,
        tutor,
        session.public_id,
        RatingCreate(score=4),
    )

    profile = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == student.id)
    )
    assert profile is None, "rating a student created them a tutor profile"

    # The tutor's own profile is still absent: nobody has reviewed a competency
    # for them, so they have not been assessed as a tutor at all.
    tutor_profile = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == tutor.id)
    )
    assert tutor_profile is None


async def test_reading_the_summary_does_not_create_a_profile(db_session) -> None:
    """A `GET` must never change state.

    The summary used to call `_get_or_create_tutor_profile`, so merely opening
    the screen would hand every signed-in student a standing.
    """
    student, _tutor, _session, _course_unit, _other = await _seed(db_session)

    summary = await rating_service.get_tutor_rating_summary(db_session, student)

    assert summary.rating_count == 0
    assert summary.rating_total == Decimal("0")
    assert summary.average_rating is None
    assert summary.per_unit == []

    profile = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == student.id)
    )
    assert profile is None, "reading the summary created a tutor profile"

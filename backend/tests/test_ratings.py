"""Tutor rating loop and standing updates."""

from datetime import UTC, datetime
from decimal import Decimal

import pytest
from sqlalchemy import select

from app.core.exceptions import ValidationProblem
from app.models.course_unit import CourseUnit, Subject, University
from app.models.enums import SessionStatus, TutorStanding, UserRole
from app.models.grading_scale import Grade, GradingScale
from app.models.session import Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User, set_roles
from app.schemas.rating import RatingCreate
from app.services import rating_service


async def _seed_session(db_session):
    scale = GradingScale(
        name="Makerere 5-point",
        max_points=Decimal("5.00"),
        competency_min_points=Decimal("4.00"),
    )
    university = University(name="Makerere University", grading_scale=scale)
    subject = Subject(name="Computer Science")
    grade = Grade(
        label="A",
        grade_points=Decimal("4.50"),
        max_points=Decimal("5.00"),
        grading_scale=scale,
    )
    course_unit = CourseUnit(
        code="CSC 121",
        name="Algorithms",
        subject=subject,
        university=university,
        grade=grade,
    )

    student = User(
        email="student@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Student Example",
        university=university,
    )
    tutor = User(
        email="tutor@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Tutor Example",
        university=university,
    )
    db_session.add_all([scale, university, subject, grade, course_unit, student, tutor])
    await db_session.flush()
    profile = TutorProfile(
        user=tutor,
        standing=TutorStanding.PROBATIONARY,
        completed_sessions=3,
        rating_total=Decimal("12.30"),
        rating_count=3,
    )
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
    db_session.add_all([profile, session])
    await db_session.flush()
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})
    return student, tutor, session, profile


async def test_submit_rating_promotes_a_tutor_to_verified(db_session):
    student, _tutor, session, profile = await _seed_session(db_session)

    rating = await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=5, feedback_text="Great session"),
    )

    assert rating.score == 5
    assert profile.standing is TutorStanding.VERIFIED
    assert profile.average_rating == Decimal("4.325")
    assert profile.rating_count == 4


async def test_submit_rating_reduces_standing_when_average_falls_below_bar(db_session):
    student = User(
        email="student2@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Student Two",
    )
    tutor = User(
        email="tutor2@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Tutor Two",
    )
    from app.models.course_unit import CourseUnit, Subject, University

    university = University(name="Makerere University")
    subject = Subject(name="Computer Science")
    course_unit = CourseUnit(
        code="CSC 221",
        name="Data Structures",
        subject=subject,
        university=university,
    )
    db_session.add_all([student, tutor, university, subject, course_unit])
    await db_session.flush()
    profile = TutorProfile(
        user=tutor,
        standing=TutorStanding.VERIFIED,
        completed_sessions=3,
        rating_total=Decimal("12.00"),
        rating_count=3,
    )
    session = Session(
        tutee_id=student.id,
        tutor_id=tutor.id,
        course_unit_id=course_unit.id,
        topic="Hash tables",
        status=SessionStatus.COMPLETED,
        started_at=datetime.now(UTC),
        ended_at=datetime.now(UTC),
        duration_minutes=60,
    )
    db_session.add_all([profile, session])
    await db_session.flush()
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})

    await rating_service.submit_rating(
        db_session,
        student,
        session.public_id,
        RatingCreate(score=3),
    )

    assert profile.standing is TutorStanding.REDUCED
    assert profile.average_rating == Decimal("3.75")


async def test_rating_submission_rejects_non_completed_sessions(db_session):
    student = User(
        email="student3@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Student Three",
    )
    tutor = User(
        email="tutor3@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Tutor Three",
    )
    university = University(name="Uni")
    subject = Subject(name="Maths")
    course_unit = CourseUnit(
        code="MTH 123",
        name="Graph Theory",
        subject=subject,
        university=university,
    )
    db_session.add_all([student, tutor, university, subject, course_unit])
    await db_session.flush()
    session = Session(
        tutee_id=student.id,
        tutor_id=tutor.id,
        course_unit_id=course_unit.id,
        topic="Graphs",
        status=SessionStatus.SCHEDULED,
        duration_minutes=60,
    )
    db_session.add(session)
    await db_session.flush()

    with pytest.raises(ValidationProblem, match="completed"):
        await rating_service.submit_rating(
            db_session,
            student,
            session.public_id,
            RatingCreate(score=4),
        )


# --- the wire contract -----------------------------------------------------
#
# The three tests above call `rating_service` directly. That proves the rules
# but not the route, the auth guard, or the response shape, and a route wired to
# the wrong dependency passes every one of them. Everything below goes through
# the real router with a real access token.

GOOD_PASSWORD = "correct horse battery staple"


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

    Registering through the router is the only way to get a row that carries a
    usable password hash, so the session is attached to the account afterwards
    rather than the account being forged around a seeded user.
    """
    body = await _register(client, email)
    user = await db_session.scalar(select(User).where(User.email == email))
    assert user is not None
    return body, user


async def test_rating_through_the_router_promotes_and_serialises(
    client, db_session
) -> None:
    """A real POST through the real route, asserted on the real response."""
    scale = GradingScale(
        name="Makerere 5-point",
        max_points=Decimal("5.00"),
        competency_min_points=Decimal("4.00"),
    )
    university = University(name="Makerere University", grading_scale=scale)
    subject = Subject(name="Computer Science")
    grade = Grade(
        label="A",
        grade_points=Decimal("4.50"),
        max_points=Decimal("5.00"),
        grading_scale=scale,
    )
    course_unit = CourseUnit(
        code="CSC 121",
        name="Algorithms",
        subject=subject,
        university=university,
        grade=grade,
    )
    db_session.add_all([scale, university, subject, grade, course_unit])
    await db_session.flush()

    student_body, student = await _registered_party(
        client, db_session, "wire-student@mak.ac.ug"
    )
    tutor_body, tutor = await _registered_party(
        client, db_session, "wire-tutor@mak.ac.ug"
    )
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})
    profile = TutorProfile(
        user=tutor,
        standing=TutorStanding.PROBATIONARY,
        completed_sessions=3,
        rating_total=Decimal("12.30"),
        rating_count=3,
    )
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
    db_session.add_all([profile, session])
    await db_session.commit()

    response = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 5, "feedback_text": "Explained quick sort clearly"},
        headers=_bearer(student_body),
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["score"] == 5
    assert body["feedback_text"] == "Explained quick sort clearly"
    # The wire carries ids as strings; `public_id` is a UUID. Compare the
    # string forms, which is what the client actually receives.
    assert body["rater_id"] == str(student.public_id)
    assert body["ratee_id"] == str(tutor.public_id)
    assert body["session_id"] == str(session.public_id)
    assert profile.rating_count == 4
    assert profile.standing is TutorStanding.VERIFIED
    assert tutor_body["user"]["email"] == "wire-tutor@mak.ac.ug"


async def test_rating_through_the_router_requires_authentication(
    client, db_session
) -> None:
    _student, _tutor, session, _profile = await _seed_session(db_session)

    response = await client.post(f"/v1/ratings/{session.public_id}", json={"score": 5})

    assert response.status_code == 401, response.text


async def test_rating_through_the_router_rejects_a_non_participant(
    client, db_session
) -> None:
    """A signed-in student who was not in the session cannot rate it."""
    _student, _tutor, session, _profile = await _seed_session(db_session)
    outsider = await _register(client, "outsider@mak.ac.ug")

    response = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 1},
        headers=_bearer(outsider),
    )

    assert response.status_code in (403, 404), response.text


async def test_rating_an_unknown_session_is_a_404(client, db_session) -> None:
    _student, _tutor, _session, _profile = await _seed_session(db_session)
    body = await _register(client, "ghost@mak.ac.ug")

    response = await client.post(
        "/v1/ratings/00000000-0000-0000-0000-000000000000",
        json={"score": 5},
        headers=_bearer(body),
    )

    assert response.status_code == 404, response.text


async def test_rating_twice_updates_rather_than_double_counts(
    client, db_session
) -> None:
    """The second rating replaces the first and the total moves by the delta."""
    _student, _tutor, session, profile = await _seed_session(db_session)
    body = await _register(client, "twice@mak.ac.ug")
    # Adopt the registered account as the session's tutee so the token in
    # `body` belongs to a party of the session.
    adopter = await db_session.scalar(
        select(User).where(User.email == "twice@mak.ac.ug")
    )
    assert adopter is not None
    session.tutee_id = adopter.id
    await db_session.commit()

    first = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 5},
        headers=_bearer(body),
    )
    assert first.status_code == 201, first.text

    second = await client.post(
        f"/v1/ratings/{session.public_id}",
        json={"score": 1, "feedback_text": "reconsidered"},
        headers=_bearer(body),
    )
    assert second.status_code == 201, second.text

    assert second.json()["score"] == 1
    assert second.json()["feedback_text"] == "reconsidered"
    # One rating from this rater, counted once, at its latest value. The seeded
    # total is 12.30: +5 for the first submission, then -5 +1 when it is
    # replaced, so the total settles at 13.30 rather than 8.30.
    assert profile.rating_count == 4
    assert profile.rating_total == Decimal("13.30")
    assert profile.standing is TutorStanding.REDUCED


async def test_rating_summary_through_the_router(client, db_session) -> None:
    _student, _tutor, _session, profile = await _seed_session(db_session)
    body = await _register(client, "summary-tutor@mak.ac.ug")
    adopter = await db_session.scalar(
        select(User).where(User.email == "summary-tutor@mak.ac.ug")
    )
    assert adopter is not None
    adopted = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == profile.user_id)
    )
    assert adopted is not None
    # Move the seeded profile onto the account the token belongs to.
    adopted.user_id = adopter.id
    await db_session.commit()

    response = await client.get("/v1/ratings/me", headers=_bearer(body))

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["rating_count"] == profile.rating_count
    # JSON has no decimal type, so the wire carries a number. Compare as Decimal
    # so a trailing-zero difference is not read as a mismatch.
    assert Decimal(str(payload["rating_total"])) == profile.rating_total
    assert isinstance(payload["recent"], list)


async def test_recent_ratings_through_the_router(client, db_session) -> None:
    _student, _tutor, _session, profile = await _seed_session(db_session)
    body = await _register(client, "recent-tutor@mak.ac.ug")
    adopter = await db_session.scalar(
        select(User).where(User.email == "recent-tutor@mak.ac.ug")
    )
    assert adopter is not None
    adopted = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == profile.user_id)
    )
    assert adopted is not None
    adopted.user_id = adopter.id
    await db_session.commit()

    response = await client.get("/v1/ratings/me/recent", headers=_bearer(body))

    assert response.status_code == 200, response.text
    assert isinstance(response.json(), list)


async def test_the_session_scoped_rating_alias_is_gone(client, db_session) -> None:
    """One operation, one route.

    The aliases were registered as `session_router` and collided with the
    sessions module. A client must not be able to reach the rating operation at
    a second path.
    """
    _student, _tutor, session, _profile = await _seed_session(db_session)
    body = await _register(client, "alias@mak.ac.ug")

    response = await client.post(
        f"/v1/sessions/{session.public_id}/ratings",
        json={"score": 5},
        headers=_bearer(body),
    )

    assert response.status_code == 404, response.text


async def test_the_nested_rating_alias_is_gone(client, db_session) -> None:
    _student, _tutor, session, _profile = await _seed_session(db_session)
    body = await _register(client, "nested@mak.ac.ug")

    response = await client.post(
        f"/v1/ratings/{session.public_id}/ratings",
        json={"score": 5},
        headers=_bearer(body),
    )

    assert response.status_code == 404, response.text

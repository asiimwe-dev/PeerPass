"""Tutor rating loop and standing updates."""

from datetime import UTC, datetime
from decimal import Decimal

import pytest

from app.core.exceptions import ValidationProblem
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
    from app.models.course_unit import CourseUnit, Subject, University

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
    from app.models.course_unit import CourseUnit, Subject, University

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

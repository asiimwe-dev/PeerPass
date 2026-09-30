"""Session lifecycle tests."""

from decimal import Decimal

import pytest
from sqlalchemy import select

from app.core.exceptions import ValidationProblem
from app.models.competency import Competency
from app.models.course_unit import CourseUnit, Subject, University
from app.models.enums import (
    CompetencyStatus,
    HelpRequestStatus,
    SessionStatus,
    TutorStanding,
    UserRole,
    VerificationSource,
)
from app.models.grading_scale import Grade, GradingScale
from app.models.session import HelpRequest, Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User, set_roles
from app.schemas.session import HelpRequestCreate, SessionCreate, SessionTransitionRequest
from app.services import matching_service, session_service


async def _seed_session_data(db_session):
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
    tutor_profile = TutorProfile(
        user=tutor,
        standing=TutorStanding.VERIFIED,
        completed_sessions=12,
        rating_total=Decimal("42.00"),
        rating_count=10,
    )
    competency = Competency(
        user=tutor,
        course_unit=course_unit,
        grade=grade,
        status=CompetencyStatus.VERIFIED,
        source=VerificationSource.TRANSCRIPT,
    )
    db_session.add_all(
        [
            scale,
            university,
            subject,
            grade,
            course_unit,
            student,
            tutor,
            tutor_profile,
            competency,
        ]
    )
    await db_session.flush()
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})
    await db_session.commit()
    return student, tutor, course_unit


async def test_create_session_from_help_request_and_generate_pin(db_session):
    student, tutor, course_unit = await _seed_session_data(db_session)
    request = await matching_service.create_help_request(
        db_session,
        student,
        HelpRequestCreate(
            course_unit_id=course_unit.public_id,
            topic="quick sort",
            description="Need help with partitioning.",
        ),
    )
    help_request = await db_session.scalar(
        select(HelpRequest).where(HelpRequest.public_id == request.id)
    )
    help_request.matched_tutor_id = tutor.id
    help_request.status = HelpRequestStatus.MATCHED
    await db_session.commit()

    session = await session_service.create_session(
        db_session,
        tutor,
        SessionCreate(
            help_request_id=request.id,
            course_unit_id=course_unit.public_id,
            topic="quick sort",
            duration_minutes=60,
            meeting_link="https://meet.google.com/demo",
        ),
    )

    assert session.tutee_id == student.public_id
    assert session.tutor_id == tutor.public_id
    assert session.status is SessionStatus.SCHEDULED
    assert session.session_pin is not None and len(session.session_pin) == 2
    assert session.meeting_link == "https://meet.google.com/demo"

    refreshed = await db_session.scalar(
        select(HelpRequest).where(HelpRequest.id == help_request.id)
    )
    assert refreshed is not None and refreshed.status is HelpRequestStatus.MATCHED


async def test_starting_a_session_requires_the_correct_pin(db_session):
    student, tutor, course_unit = await _seed_session_data(db_session)
    request = await matching_service.create_help_request(
        db_session,
        student,
        HelpRequestCreate(
            course_unit_id=course_unit.public_id,
            topic="hash tables",
        ),
    )
    help_request = await db_session.scalar(
        select(HelpRequest).where(HelpRequest.public_id == request.id)
    )
    help_request.matched_tutor_id = tutor.id
    help_request.status = HelpRequestStatus.MATCHED
    await db_session.commit()
    created = await session_service.create_session(
        db_session,
        tutor,
        SessionCreate(
            help_request_id=request.id,
            course_unit_id=course_unit.public_id,
            topic="hash tables",
            duration_minutes=90,
        ),
    )

    with pytest.raises(ValidationProblem, match="PIN"):
        await session_service.transition_session(
            db_session,
            tutor,
            created.id,
            SessionTransitionRequest(status=SessionStatus.IN_PROGRESS, pin="99"),
        )

    started = await session_service.transition_session(
        db_session,
        tutor,
        created.id,
        SessionTransitionRequest(status=SessionStatus.IN_PROGRESS, pin=created.session_pin),
    )

    assert started.status is SessionStatus.IN_PROGRESS
    assert started.started_at is not None


async def test_marking_a_session_complete_stops_the_clock(db_session):
    student, tutor, course_unit = await _seed_session_data(db_session)
    request = await matching_service.create_help_request(
        db_session,
        student,
        HelpRequestCreate(
            course_unit_id=course_unit.public_id,
            topic="sorting",
        ),
    )
    help_request = await db_session.scalar(
        select(HelpRequest).where(HelpRequest.public_id == request.id)
    )
    help_request.matched_tutor_id = tutor.id
    help_request.status = HelpRequestStatus.MATCHED
    await db_session.commit()
    created = await session_service.create_session(
        db_session,
        tutor,
        SessionCreate(
            help_request_id=request.id,
            course_unit_id=course_unit.public_id,
            topic="sorting",
            duration_minutes=45,
        ),
    )

    started = await session_service.transition_session(
        db_session,
        tutor,
        created.id,
        SessionTransitionRequest(status=SessionStatus.IN_PROGRESS, pin=created.session_pin),
    )
    completed = await session_service.transition_session(
        db_session,
        tutor,
        started.id,
        SessionTransitionRequest(status=SessionStatus.COMPLETED),
    )

    assert completed.status is SessionStatus.COMPLETED
    assert completed.duration_minutes >= 1
    assert completed.ended_at is not None
    assert completed.is_rated is False

    session_row = await db_session.scalar(
        select(Session).where(Session.public_id == created.id)
    )
    assert session_row is not None and session_row.status is SessionStatus.COMPLETED

"""Matching tests."""

from decimal import Decimal

from app.models.competency import Competency
from app.models.course_unit import CourseUnit, Subject, University
from app.models.enums import (
    CompetencyStatus,
    TutorStanding,
    UserRole,
    VerificationSource,
)
from app.models.grading_scale import Grade, GradingScale
from app.models.tutor_profile import TutorProfile
from app.models.user import User, set_roles
from app.schemas.matching import MatchRequest
from app.schemas.session import HelpRequestCreate
from app.services import matching_service


async def _seed_match_data(db_session):
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


async def test_create_help_request_and_match_tutors(db_session):
    student, _tutor, course_unit = await _seed_match_data(db_session)

    request = await matching_service.create_help_request(
        db_session,
        student,
        HelpRequestCreate(
            course_unit_id=course_unit.public_id,
            topic="quick sort",
            description="Need help understanding partitions.",
        ),
    )
    response = await matching_service.match_tutors(
        db_session,
        student,
        MatchRequest(course_unit_id=course_unit.public_id, limit=5),
    )

    assert request.course_unit_id == course_unit.public_id
    assert response.no_eligible_tutors is False
    assert response.candidates
    assert response.candidates[0].tutor.full_name == "Tutor Example"


async def test_tutor_from_other_university_is_excluded(db_session):
    home_scale = GradingScale(
        name="Home scale",
        max_points=Decimal("5.00"),
        competency_min_points=Decimal("4.00"),
    )
    home_university = University(name="Home University", grading_scale=home_scale)
    other_university = University(name="Other University", grading_scale=home_scale)
    subject = Subject(name="Mathematics")
    grade = Grade(
        label="A",
        grade_points=Decimal("4.50"),
        max_points=Decimal("5.00"),
        grading_scale=home_scale,
    )
    course_unit = CourseUnit(
        code="MTH 101",
        name="Calculus",
        subject=subject,
        university=home_university,
        grade=grade,
    )
    student = User(
        email="student@home.ac.ug",
        password_hash="hashed-password",
        full_name="Student Example",
        university=home_university,
    )
    tutor = User(
        email="tutor@other.ac.ug",
        password_hash="hashed-password",
        full_name="Other Tutor",
        university=other_university,
    )
    db_session.add_all(
        [
            home_scale,
            home_university,
            other_university,
            subject,
            grade,
            course_unit,
            student,
            tutor,
        ]
    )
    await db_session.flush()
    await set_roles(db_session, tutor.id, {UserRole.TUTOR})
    db_session.add(
        TutorProfile(
            user=tutor,
            standing=TutorStanding.VERIFIED,
            completed_sessions=7,
            rating_total=Decimal("30.00"),
            rating_count=7,
        )
    )
    db_session.add(
        Competency(
            user=tutor,
            course_unit=course_unit,
            grade=grade,
            status=CompetencyStatus.VERIFIED,
            source=VerificationSource.TRANSCRIPT,
        )
    )
    await db_session.commit()

    response = await matching_service.match_tutors(
        db_session,
        student,
        MatchRequest(course_unit_id=course_unit.public_id, limit=5),
    )

    assert response.no_eligible_tutors is True
    assert any(item.reason == "same_university_only" for item in response.exclusions)

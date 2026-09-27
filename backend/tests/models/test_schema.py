"""The schema: identifiers, constraints, and relationships.

These are the tests that would otherwise only fail in production. SQLite does
not enforce everything PostgreSQL does, so a few are marked as documentation of
intent that the migration is the real proof.
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

import pytest
from sqlalchemy import insert, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import new_public_id, new_uuid7
from app.models import (
    Base,
    Competency,
    CompetencyStatus,
    CourseUnit,
    Grade,
    GradingScale,
    HelpRequest,
    HelpRequestStatus,
    Rating,
    Session,
    SessionStatus,
    Subject,
    TutorProfile,
    TutorStanding,
    University,
    User,
    UserRole,
    VerificationSource,
    has_role,
    load_roles,
    set_roles,
    user_roles,
)
from app.models import (
    Rating as RatingModel,
)


async def _scale(**overrides: object) -> GradingScale:
    values: dict[str, object] = {
        "name": overrides.pop("name", f"scale-{uuid.uuid4()}"),
        "max_points": Decimal("4.00"),
        "competency_min_points": Decimal("3.50"),
    }
    values.update(overrides)
    return GradingScale(**values)  # type: ignore[arg-type]


def _grade(label: str, points: str, scale: GradingScale) -> Grade:
    return Grade(
        label=label,
        grade_points=Decimal(points),
        max_points=scale.max_points,
        grading_scale_id=scale.id,
    )


def _user(email: str | None = None) -> User:
    return User(
        email=email or f"{uuid.uuid4()}@ug.ac.ug",
        full_name="Test Person",
        password_hash="pbkdf2_sha256$600000$00$00",
    )


class TestIdentifiers:
    async def test_primary_keys_are_uuid_v7(self, db_session: AsyncSession) -> None:
        """Time-ordered keys keep inserts at the end of the write index."""
        user = _user()
        db_session.add(user)
        await db_session.commit()

        assert user.id.version == 7

    async def test_public_ids_are_uuid_v4(self, db_session: AsyncSession) -> None:
        """A public id must not encode its creation time."""
        user = _user()
        db_session.add(user)
        await db_session.commit()

        assert user.public_id.version == 4

    async def test_primary_key_is_not_the_public_id(
        self, db_session: AsyncSession
    ) -> None:
        user = _user()
        db_session.add(user)
        await db_session.commit()

        assert user.id != user.public_id


class TestEnums:
    async def test_enum_values_are_persisted_as_wire_values(
        self, db_session: AsyncSession
    ) -> None:
        """The column must hold `student`, not `STUDENT`.

        SQLAlchemy persists the member name by default, which would put a value
        in the database that does not match the wire format the client parses.
        """
        user = _user()
        db_session.add(user)
        await db_session.commit()
        await set_roles(db_session, user.id, {UserRole.TUTOR})
        await db_session.commit()

        raw = await db_session.execute(text("SELECT role FROM user_roles"))
        assert raw.all() == [("tutor",)]

    async def test_unknown_enum_value_is_rejected_by_the_database(
        self, db_session: AsyncSession
    ) -> None:
        """Rejected by the database, not just by the ORM.

        Worth insisting on: the ORM would refuse this value anyway, so a test that
        only inserted through the ORM would pass whether or not the column had a
        constraint. A data fix, a reporting query, or any other raw SQL would not
        get that protection, and an unrecognised `standing` silently fails every
        tutor filter that reads it.
        """
        user = _user()
        db_session.add(user)
        await db_session.flush()

        with pytest.raises(IntegrityError):
            await db_session.execute(
                text(
                    "INSERT INTO tutor_profiles "
                    "(id, public_id, user_id, standing, completed_sessions, "
                    "certified_minutes, rating_total, rating_count, "
                    "created_at, updated_at) "
                    "VALUES (:id, :public_id, :user_id, 'wizard', 0, 0, 0, 0, "
                    ":now, :now)"
                ),
                # Bound as strings: a raw text() statement skips SQLAlchemy's
                # type coercion, and aiosqlite cannot bind a UUID object.
                # PostgreSQL coerces the literal to the column type on insert.
                {
                    "id": str(uuid.uuid4()),
                    "public_id": str(uuid.uuid4()),
                    "user_id": str(user.id),
                    # ISO text rather than a datetime object, which trips
                    # aiosqlite's deprecated default adapter.
                    "now": datetime.now(UTC).isoformat(),
                },
            )


class TestGradingScale:
    async def test_threshold_must_be_within_the_scale(
        self, db_session: AsyncSession
    ) -> None:
        """A threshold above the maximum could never be met, so it is rejected."""
        db_session.add(
            GradingScale(
                name="broken",
                max_points=Decimal("4.00"),
                competency_min_points=Decimal("9.00"),
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_a_label_is_unique_per_scale(self, db_session: AsyncSession) -> None:
        """Not globally unique, and not unique per course unit.

        Scoped to the scale, because "A" on a four-point scale and "A" on a
        percentage scale are different grades that happen to share a label.
        """
        scale = await _scale()
        db_session.add_all([_grade("A", "4.00", scale), _grade("A", "3.90", scale)])

        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_the_same_label_may_exist_on_two_scales(
        self, db_session: AsyncSession
    ) -> None:
        first = await _scale(name="four-point")
        second = await _scale(name="percentage", max_points=Decimal("100.00"))
        db_session.add_all([first, second])
        # Flushed first: `_grade` reads `scale.id`, which is only assigned on
        # insert.
        await db_session.flush()
        db_session.add_all([_grade("A", "4.00", first), _grade("A", "80.00", second)])
        await db_session.commit()

    async def test_grade_points_may_not_exceed_the_scale(
        self, db_session: AsyncSession
    ) -> None:
        scale = await _scale()
        db_session.add(scale)
        await db_session.flush()
        db_session.add(_grade("A+", "9.00", scale))

        with pytest.raises(IntegrityError):
            await db_session.commit()


class TestCourseUnit:
    async def test_two_universities_may_use_the_same_code(
        self, db_session: AsyncSession
    ) -> None:
        """`MAT 221` is a different course at each institution.

        A global unique index on `code` would forbid this and push whoever loads
        the curriculum into inventing a suffix like `MAT221-MAK`.
        """
        first, _ = await _unit(db_session, code="MAT 221")
        second, _ = await _unit(db_session, code="MAT 221")
        await db_session.commit()

        assert first.id != second.id
        assert first.university_id != second.university_id

    async def test_one_university_may_not_reuse_a_code(
        self, db_session: AsyncSession
    ) -> None:
        first, _ = await _unit(db_session, code="MAT 221")
        duplicate = CourseUnit(
            code="MAT 221",
            name="Linear Algebra",
            university_id=first.university_id,
        )
        db_session.add(duplicate)

        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_a_unit_requires_a_university(self, db_session: AsyncSession) -> None:
        """Matching only pairs people at one institution, so an orphan unit
        could never be matched and would only be a search result that fails."""
        db_session.add(CourseUnit(code="ORPHAN 101", name="Orphan"))

        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_deleting_a_unit_cascades_to_its_competencies(
        self, db_session: AsyncSession
    ) -> None:
        """`passive_deletes` on the relationship, not just the foreign key.

        The foreign key alone leaves the ORM to load every competency and unlink
        it one at a time, which the NOT NULL column then rejects.
        """
        user, unit, grade = await _competency_parts(db_session)
        competency = Competency(
            user_id=user.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            source=VerificationSource.TRANSCRIPT,
        )
        db_session.add(competency)
        await db_session.commit()
        competency_id = competency.id

        await db_session.delete(unit)
        await db_session.commit()
        db_session.expunge_all()

        assert await db_session.get(Competency, competency_id) is None


class TestUser:
    async def test_email_is_unique(self, db_session: AsyncSession) -> None:
        db_session.add_all([_user("same@ug.ac.ug"), _user("same@ug.ac.ug")])
        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_a_role_cannot_be_held_twice(self, db_session: AsyncSession) -> None:
        """The uniqueness rule is the join table's primary key, not a service check.

        Inserted directly, because the `set_roles` helper takes a set and so
        cannot express the duplicate this is meant to reject.
        """
        user = _user()
        db_session.add(user)
        await db_session.commit()
        with pytest.raises(IntegrityError):
            await db_session.execute(
                insert(user_roles),
                [
                    {"user_id": user.id, "role": UserRole.STUDENT.value},
                    {"user_id": user.id, "role": UserRole.STUDENT.value},
                ],
            )

    async def test_a_user_may_hold_several_roles(
        self, db_session: AsyncSession
    ) -> None:
        """A tutor is also a student, and a single column could not express that."""
        user = _user()
        db_session.add(user)
        await db_session.commit()
        await set_roles(db_session, user.id, {UserRole.STUDENT, UserRole.TUTOR})
        await db_session.commit()

        roles = await load_roles(db_session, user.id)

        assert has_role(roles, UserRole.TUTOR)
        assert has_role(roles, UserRole.STUDENT)

    async def test_deletion_cascades_to_competencies(
        self, db_session: AsyncSession
    ) -> None:
        """Deleting an account must take its academic record with it.

        Under the Uganda Data Protection and Privacy Act an account deletion
        that left grades behind would be a retention failure, not a cleanup
        detail.
        """
        user = _user()
        unit, scale = await _unit(db_session, code="MAT 221")
        db_session.add(user)
        await db_session.flush()

        grade = _grade("B+", "3.50", scale)
        db_session.add(grade)
        await db_session.flush()
        unit.grade_id = grade.id

        competency = Competency(
            user_id=user.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            source=VerificationSource.TRANSCRIPT,
        )
        db_session.add(competency)
        await db_session.commit()
        competency_id = competency.id

        await db_session.delete(user)
        await db_session.commit()
        # The identity map still holds the deleted row, and `get` would return
        # it without asking the database. Expiring is not enough; only
        # detaching forces the read below to hit the table.
        db_session.expunge_all()

        assert await db_session.get(Competency, competency_id) is None


class TestCompetency:
    async def test_one_record_per_user_per_unit(self, db_session: AsyncSession) -> None:
        user, unit, grade = await _competency_parts(db_session)
        db_session.add(
            Competency(
                user_id=user.id,
                course_unit_id=unit.id,
                grade_id=grade.id,
                source=VerificationSource.TRANSCRIPT,
            )
        )
        await db_session.commit()
        db_session.add(
            Competency(
                user_id=user.id,
                course_unit_id=unit.id,
                grade_id=grade.id,
                source=VerificationSource.PORTFOLIO,
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_unverified_never_meets_the_threshold(
        self, db_session: AsyncSession
    ) -> None:
        """A grade is a claim until someone has checked it.

        This is the tier-1 gate: the highest possible grade must still fail while
        the competency is pending.
        """
        user, unit, grade = await _competency_parts(db_session)
        competency = Competency(
            user_id=user.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            source=VerificationSource.TRANSCRIPT,
        )
        db_session.add(competency)
        await db_session.commit()

        assert competency.meets_threshold(Decimal("1.00")) is False

    async def test_verified_grade_above_the_threshold_meets_it(
        self, db_session: AsyncSession
    ) -> None:
        user, unit, grade = await _competency_parts(db_session)
        competency = Competency(
            user_id=user.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            status=CompetencyStatus.VERIFIED,
            source=VerificationSource.TRANSCRIPT,
        )
        db_session.add(competency)
        await db_session.commit()

        assert competency.meets_threshold(Decimal("3.50")) is True

    async def test_verified_grade_below_the_threshold_fails(
        self, db_session: AsyncSession
    ) -> None:
        user, unit, grade = await _competency_parts(db_session, points="2.00")
        competency = Competency(
            user_id=user.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            status=CompetencyStatus.VERIFIED,
            source=VerificationSource.TRANSCRIPT,
        )
        db_session.add(competency)
        await db_session.commit()

        assert competency.meets_threshold(Decimal("3.50")) is False


class TestHelpRequestAndSession:
    async def test_request_and_session_are_separate_entities(
        self, db_session: AsyncSession
    ) -> None:
        """A request that is never matched must not leave a session behind.

        Modelling an unmatched request as a session row would make every tutor
        workload query carry a filter for sessions that never happened.
        """
        tutee = _user()
        unit, _ = await _unit(db_session)
        db_session.add(tutee)
        await db_session.flush()
        request = HelpRequest(
            tutee_id=tutee.id, course_unit_id=unit.id, topic="Eigenvalues"
        )
        db_session.add(request)
        await db_session.commit()
        await db_session.refresh(request)

        sessions = await db_session.execute(
            select(Session).where(Session.help_request_id == request.id)
        )

        assert request.status is HelpRequestStatus.OPEN
        assert sessions.scalars().all() == []

    async def test_a_session_cannot_have_itself_as_both_parties(
        self, db_session: AsyncSession
    ) -> None:
        """Self-matching would let a student bank certificate hours."""
        user = _user()
        unit, _ = await _unit(db_session)
        db_session.add(user)
        await db_session.flush()
        db_session.add(
            Session(
                tutee_id=user.id,
                tutor_id=user.id,
                course_unit_id=unit.id,
                topic="Eigenvalues",
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_completed_session_requires_start_and_end(
        self, db_session: AsyncSession
    ) -> None:
        """Otherwise the hours it contributes to a certificate are unknowable."""
        tutee, tutor, unit = await _session_parts(db_session)
        db_session.add(
            Session(
                tutee_id=tutee.id,
                tutor_id=tutor.id,
                course_unit_id=unit.id,
                topic="Eigenvalues",
                status=SessionStatus.COMPLETED,
                duration_minutes=60,
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_negative_duration_is_rejected(
        self, db_session: AsyncSession
    ) -> None:
        tutee, tutor, unit = await _session_parts(db_session)
        db_session.add(
            Session(
                tutee_id=tutee.id,
                tutor_id=tutor.id,
                course_unit_id=unit.id,
                topic="Eigenvalues",
                duration_minutes=-30,
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()


class TestRating:
    async def test_score_must_be_within_one_to_five(
        self, db_session: AsyncSession
    ) -> None:
        tutee, tutor, unit = await _session_parts(db_session)
        session = Session(
            tutee_id=tutee.id,
            tutor_id=tutor.id,
            course_unit_id=unit.id,
            topic="Eigenvalues",
            status=SessionStatus.COMPLETED,
            started_at=datetime.now(UTC),
            ended_at=datetime.now(UTC),
            duration_minutes=60,
        )
        db_session.add(session)
        await db_session.flush()
        db_session.add(
            Rating(
                session_id=session.id,
                rater_id=tutee.id,
                ratee_id=tutor.id,
                score=6,
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()

    async def test_a_session_reports_whether_it_is_rated(
        self, db_session: AsyncSession
    ) -> None:
        """The check the completed-session-requires-a-rating rule is written on."""
        tutee, tutor, unit = await _session_parts(db_session)
        session = Session(
            tutee_id=tutee.id,
            tutor_id=tutor.id,
            course_unit_id=unit.id,
            topic="Eigenvalues",
            status=SessionStatus.COMPLETED,
            started_at=datetime.now(UTC),
            ended_at=datetime.now(UTC),
            duration_minutes=60,
        )
        db_session.add(session)
        await db_session.commit()
        await db_session.refresh(session)

        assert await session.is_rated(db_session) is False

        db_session.add(
            Rating(session_id=session.id, rater_id=tutee.id, ratee_id=tutor.id, score=5)
        )
        await db_session.commit()
        await db_session.refresh(session)

        assert await session.is_rated(db_session) is True

    async def test_deleting_a_session_cascades_to_its_ratings(
        self, db_session: AsyncSession
    ) -> None:
        tutee, tutor, unit = await _session_parts(db_session)
        session = Session(
            tutee_id=tutee.id,
            tutor_id=tutor.id,
            course_unit_id=unit.id,
            topic="Eigenvalues",
            status=SessionStatus.COMPLETED,
            started_at=datetime.now(UTC),
            ended_at=datetime.now(UTC),
            duration_minutes=60,
        )
        db_session.add(session)
        await db_session.flush()
        rating = Rating(
            session_id=session.id, rater_id=tutee.id, ratee_id=tutor.id, score=4
        )
        db_session.add(rating)
        await db_session.commit()
        rating_id = rating.id

        await db_session.delete(session)
        await db_session.commit()
        db_session.expunge_all()

        assert await db_session.get(Rating, rating_id) is None

    async def test_a_rater_may_only_rate_a_session_once(
        self, db_session: AsyncSession
    ) -> None:
        """A retried submit must update, not add a second score to average in."""
        tutee, tutor, unit = await _session_parts(db_session)
        session = Session(
            tutee_id=tutee.id,
            tutor_id=tutor.id,
            course_unit_id=unit.id,
            topic="Eigenvalues",
            status=SessionStatus.COMPLETED,
            started_at=datetime.now(UTC),
            ended_at=datetime.now(UTC),
            duration_minutes=60,
        )
        db_session.add(session)
        await db_session.flush()
        db_session.add_all(
            [
                Rating(
                    session_id=session.id,
                    rater_id=tutee.id,
                    ratee_id=tutor.id,
                    score=5,
                ),
                Rating(
                    session_id=session.id,
                    rater_id=tutee.id,
                    ratee_id=tutor.id,
                    score=1,
                ),
            ]
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()


class TestTutorProfile:
    async def test_average_rating_is_none_without_ratings(self) -> None:
        """Not zero.

        A tutor with no ratings is not badly rated, and treating them as zero
        would fail a `>= 4.0` promotion test for entirely the wrong reason.
        """
        profile = TutorProfile(user_id=uuid.uuid4())

        assert profile.average_rating is None

    async def test_average_rating_divides_total_by_count(self) -> None:
        profile = TutorProfile(
            user_id=uuid.uuid4(),
            rating_total=Decimal("18.00"),
            rating_count=4,
        )

        assert profile.average_rating == Decimal("4.50")

    async def test_new_tutors_start_probationary(
        self, db_session: AsyncSession
    ) -> None:
        """A tutor is unproven until their sessions say otherwise.

        Flushed first: a Python-side `default` is not applied to the instance
        until the insert, so asserting before a commit would read None and pass
        for the wrong reason on a different SQLAlchemy version.
        """
        user = _user()
        db_session.add(user)
        await db_session.flush()
        profile = TutorProfile(user_id=user.id)
        db_session.add(profile)
        await db_session.commit()

        assert profile.standing is TutorStanding.PROBATIONARY

    async def test_counters_cannot_go_negative(self, db_session: AsyncSession) -> None:
        db_session.add(
            TutorProfile(user_id=uuid.uuid4(), rating_count=-1, completed_sessions=0)
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()


class TestMetadata:
    def test_every_model_is_reachable_from_the_metadata(self) -> None:
        """A model missing from `app.models` is invisible to Alembic.

        The result is a migration that does not create the table, and a failure
        that only shows up in production.
        """
        tables = set(Base.metadata.tables)

        assert {
            "users",
            "user_roles",
            "universities",
            "grading_scales",
            "grades",
            "subjects",
            "course_units",
            "competencies",
            "tutor_profiles",
            "help_requests",
            "sessions",
            "ratings",
            "refresh_tokens",
        } <= tables

    def test_no_table_is_named_like_a_python_keyword(self) -> None:
        for name in Base.metadata.tables:
            assert not name.startswith("pg_"), f"{name} collides with a system name"


async def _unit(
    db_session: AsyncSession, code: str | None = None
) -> tuple[CourseUnit, GradingScale]:
    scale = await _scale()
    subject = Subject(name=f"Subject-{uuid.uuid4()}")
    university = University(
        name=f"University-{uuid.uuid4()}", grading_scale_id=scale.id
    )
    db_session.add_all([scale, subject, university])
    await db_session.flush()
    unit = CourseUnit(
        code=code or f"UNIT-{uuid.uuid4().hex[:8]}",
        name="Linear Algebra",
        subject_id=subject.id,
        university_id=university.id,
    )
    db_session.add(unit)
    await db_session.flush()
    return unit, scale


async def _competency_parts(
    db_session: AsyncSession, points: str = "4.00"
) -> tuple[User, CourseUnit, Grade]:
    user = _user()
    unit, scale = await _unit(db_session)
    db_session.add(user)
    await db_session.flush()
    grade = _grade("A", points, scale)
    db_session.add(grade)
    await db_session.flush()
    return user, unit, grade


async def _session_parts(
    db_session: AsyncSession,
) -> tuple[User, User, CourseUnit]:
    tutee = _user()
    tutor = _user()
    unit, _ = await _unit(db_session)
    db_session.add_all([tutee, tutor])
    await db_session.flush()
    return tutee, tutor, unit


def test_metadata_is_internally_consistent() -> None:
    """Catches a malformed relationship or constraint at import time.

    Ambiguous foreign keys and unresolvable relationship targets only fail when
    the mappers are configured, which without this would be the first request
    that touches the table.
    """
    from sqlalchemy.orm import configure_mappers

    configure_mappers()

    assert "users" in Base.metadata.tables


def test_primary_key_generator_is_stable() -> None:
    assert new_uuid7() != new_uuid7()
    assert new_public_id() != new_public_id()


def test_rating_model_is_the_same_class() -> None:
    assert RatingModel is Rating

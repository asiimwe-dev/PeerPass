"""Per-course certificate eligibility: the thresholds, and whose hours it is.

A certificate is awarded per course. These tests state that in the terms the
product uses: the same tutor can be finished in one course and nowhere near in
another, and the totals are not pooled until one course carries the others over
the bar.

The boundary tests use sessions and ratings rather than `TutorProfile` counters,
because that is where a per-course answer comes from. A test that wrote a
tutor-wide total would be testing a number the endpoint must no longer read.

The last group is the accrual rule, tested against what `record_completion`
actually does rather than against what it ought to: only a session that is
already COMPLETED contributes, and it contributes `max(duration_minutes, 0)`. A
session that was cancelled keeps the duration it was booked with and must
contribute none of it. The last test in that group is the one a client actually
walks -- session service, not a direct call to the increment.
"""

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import func, select

from app.core.config import Settings, get_settings
from app.models.competency import Competency
from app.models.course_unit import CourseUnit, Subject, University
from app.models.enums import (
    CompetencyStatus,
    SessionStatus,
    TutorStanding,
    VerificationSource,
)
from app.models.grading_scale import Grade, GradingScale
from app.models.rating import Rating
from app.models.session import Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User
from app.services import incentive_service, rating_service, session_service

GOOD_PASSWORD = "correct horse battery staple"

#: The defaults the pilot ships with, stated here so the boundary tests below say
#: "900 and 899" rather than "the configured value and one less".
DEFAULT_REQUIRED_MINUTES = 900
DEFAULT_REQUIRED_SESSIONS = 10
DEFAULT_MINIMUM_AVERAGE = Decimal("4.10")


@pytest.fixture(autouse=True)
def _threshold_from_the_environment(monkeypatch: pytest.MonkeyPatch):
    """Pin all three thresholds to their defaults for every test in this file.

    `get_settings` reads the environment and a local `.env`, so a developer's own
    `CERTIFICATE_REQUIRED_MINUTES` would otherwise decide whether a test that
    states 900 and 899 passed. The cache is cleared on the way out as well as
    on the way in, because the settings object is process-wide and a threshold
    left behind here would answer the rest of the suite.
    """
    monkeypatch.setenv("CERTIFICATE_REQUIRED_MINUTES", str(DEFAULT_REQUIRED_MINUTES))
    monkeypatch.setenv("CERTIFICATE_REQUIRED_SESSIONS", str(DEFAULT_REQUIRED_SESSIONS))
    monkeypatch.setenv("CERTIFICATE_MINIMUM_AVERAGE", str(DEFAULT_MINIMUM_AVERAGE))
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _set_threshold(monkeypatch: pytest.MonkeyPatch, minutes: int) -> None:
    """Change the configured threshold the way an operator would."""
    monkeypatch.setenv("CERTIFICATE_REQUIRED_MINUTES", str(minutes))
    get_settings.cache_clear()


# --- helpers -----------------------------------------------------------------


async def _register(client, email: str) -> dict:
    response = await client.post(
        "/v1/auth/register", json={"email": email, "password": GOOD_PASSWORD}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _bearer(body: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {body['tokens']['access_token']}"}


async def _account(client, db_session, email: str) -> tuple[dict, User]:
    """Register a real account, so the request carries a real access token."""
    body = await _register(client, email)
    user = await db_session.scalar(select(User).where(User.email == email))
    assert user is not None
    return body, user


async def _tutor(client, db_session, email: str) -> tuple[dict, User]:
    """An account with a tutor profile and no course evidence yet.

    A profile is what `has_tutor_profile` reports. It deliberately carries zero
    counters: a per-course answer must come from sessions and ratings, so a test
    that filled the profile totals instead would pass against the wrong source.
    """
    body, user = await _account(client, db_session, email)
    db_session.add(
        TutorProfile(
            user_id=user.id,
            standing=TutorStanding.PROBATIONARY,
            completed_sessions=0,
            certified_minutes=0,
            rating_total=Decimal("0"),
            rating_count=0,
        )
    )
    await db_session.commit()
    return body, user


async def _unit(
    db_session, *, code: str = "CSC 121", name: str = "Algorithms"
) -> CourseUnit:
    """A course unit with its own university and subject."""
    suffix = uuid.uuid4().hex[:8]
    university = University(name=f"University {suffix}")
    subject = Subject(name=f"Computer Science {suffix}")
    unit = CourseUnit(
        code=code,
        name=name,
        subject=subject,
        university=university,
    )
    db_session.add_all([university, subject, unit])
    await db_session.flush()
    return unit


async def _teach(
    db_session,
    tutor: User,
    unit: CourseUnit,
    *,
    minutes: int,
    sessions: int,
    scores: tuple[int, ...] = (),
) -> None:
    """Completed sessions in one course, with the ratings a tutee left.

    Minutes are spread across the sessions so a test that wants 900 minutes over
    ten sessions creates ten rows rather than one implausible one. Ratings are
    attached to the first sessions in order, because a session may be completed
    before its rating arrives and the certificate counts the rating wherever it
    is.
    """
    assert sessions > 0
    tutee = User(
        email=f"tutee-{uuid.uuid4().hex}@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Tutee Example",
    )
    db_session.add(tutee)
    await db_session.flush()

    base, remainder = divmod(minutes, sessions)
    now = datetime.now(UTC)
    for index in range(sessions):
        duration = base + (1 if index < remainder else 0)
        started = now - timedelta(minutes=max(duration, 1))
        session = Session(
            tutee_id=tutee.id,
            tutor_id=tutor.id,
            course_unit_id=unit.id,
            topic="Quick sort",
            status=SessionStatus.COMPLETED,
            started_at=started,
            ended_at=now,
            tutor_checked_in_at=started,
            tutee_checked_in_at=started,
            tutor_finished_at=now,
            tutee_finished_at=now,
            duration_minutes=duration,
        )
        db_session.add(session)
        await db_session.flush()
        if index < len(scores):
            db_session.add(
                Rating(
                    session_id=session.id,
                    rater_id=tutee.id,
                    ratee_id=tutor.id,
                    score=scores[index],
                )
            )
    await db_session.commit()


async def _verified_competency(db_session, tutor: User, unit: CourseUnit) -> None:
    """A verified claim for a course, with no sessions behind it yet."""
    scale = GradingScale(
        name=f"Scale {uuid.uuid4().hex[:8]}",
        max_points=Decimal("5"),
        competency_min_points=Decimal("4"),
    )
    grade = Grade(
        label="A",
        grade_points=Decimal("5"),
        max_points=Decimal("5"),
        grading_scale=scale,
    )
    db_session.add_all([scale, grade])
    await db_session.flush()
    db_session.add(
        Competency(
            user_id=tutor.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            status=CompetencyStatus.VERIFIED,
            source=VerificationSource.MANUAL,
            verified_at=datetime.now(UTC),
        )
    )
    await db_session.commit()


async def _session(
    db_session,
    tutor: User,
    *,
    status: SessionStatus,
    duration_minutes: int,
    started_at: datetime | None = None,
    ended_at: datetime | None = None,
    unit: CourseUnit | None = None,
) -> Session:
    """One session row, with a unit and a tutee the schema accepts."""
    unit = unit or await _unit(db_session)
    student = User(
        email=f"student-{uuid.uuid4().hex}@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Student Example",
    )
    db_session.add(student)
    await db_session.flush()
    live = status in {SessionStatus.IN_PROGRESS, SessionStatus.COMPLETED}
    attendance_start = started_at or datetime.now(UTC)
    session = Session(
        tutee_id=student.id,
        tutor_id=tutor.id,
        course_unit_id=unit.id,
        topic="Quick sort",
        status=status,
        started_at=started_at,
        ended_at=ended_at,
        tutor_checked_in_at=attendance_start if live else None,
        tutee_checked_in_at=attendance_start if live else None,
        tutor_finished_at=(ended_at or datetime.now(UTC))
        if status is SessionStatus.COMPLETED
        else None,
        tutee_finished_at=(ended_at or datetime.now(UTC))
        if status is SessionStatus.COMPLETED
        else None,
        duration_minutes=duration_minutes,
    )
    db_session.add(session)
    await db_session.flush()
    return session


async def _portfolio(client, body: dict) -> dict:
    response = await client.get("/v1/incentives/certificate", headers=_bearer(body))
    assert response.status_code == 200, response.text
    return response.json()


def _course(payload: dict, code: str) -> dict:
    for course in payload["courses"]:
        if course["course_unit_code"] == code:
            return course
    raise AssertionError(f"{code} was not in {payload['courses']}")


# --- the threshold, inside one course ----------------------------------------


async def test_exactly_the_required_minutes_is_eligible(client, db_session):
    """The boundary, from the inside. A threshold met is a threshold met."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is True
    assert course["certified_minutes"] == DEFAULT_REQUIRED_MINUTES
    assert course["remaining_minutes"] == 0
    assert course["progress"] == 1.0


async def test_one_minute_short_is_not_eligible(client, db_session):
    """The boundary, from the outside. This is the case that must not round."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES - 1,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is False
    assert course["remaining_minutes"] == 1
    # Not one hour of progress, and not a rounded 15: a bar built from either
    # would tell a tutor one minute from the threshold that they are done.
    assert course["progress"] == pytest.approx(899 / 900)


async def test_well_past_the_threshold_is_eligible_and_capped(client, db_session):
    """A tutor who taught twice the requirement is complete, not overflowing."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES * 2,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is True
    assert course["progress"] == 1.0
    assert course["remaining_minutes"] == 0


async def test_hours_alone_do_not_earn_a_certificate(client, db_session):
    """The bug the session gate exists for.

    A tutor with four very long sessions can pass the minutes threshold while
    having taught only four times. That is volume, not a sustained record, and
    the certificate must not call it one.
    """
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES * 2,
        sessions=4,
        scores=(5, 5, 5, 5),
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is False
    assert course["minutes_met"] is True
    assert course["sessions_met"] is False
    assert course["rating_met"] is False
    assert course["remaining_sessions"] == DEFAULT_REQUIRED_SESSIONS - 4
    assert course["progress"] == pytest.approx(4 / DEFAULT_REQUIRED_SESSIONS)


async def test_enough_sessions_but_too_few_ratings_is_not_eligible(client, db_session):
    """A completed session is not rated evidence until the student rates it."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(5, 5, 5),
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is False
    assert course["sessions_met"] is True
    assert course["rating_met"] is False
    assert course["rating_count"] == 3
    assert course["progress"] == pytest.approx(3 / DEFAULT_REQUIRED_SESSIONS)


async def test_enough_ratings_but_a_low_average_is_not_eligible(client, db_session):
    """Maintaining the rating bar is the second half of the rating condition."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(3,) * 5 + (4,) * 5,
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is False
    assert course["sessions_met"] is True
    assert course["rating_met"] is False
    assert course["average_rating"] == "3.50"
    assert course["progress"] == pytest.approx(3.5 / 4.1)


async def test_exactly_the_bar_on_all_three_conditions_is_eligible(client, db_session):
    """The boundary is inclusive on every requirement, not just the minutes."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["eligible"] is True
    assert course["minutes_met"] is True
    assert course["sessions_met"] is True
    assert course["rating_met"] is True
    assert course["average_rating"] == "4.10"
    assert course["progress"] == 1.0


async def test_minutes_are_sent_exactly_as_stored(client, db_session):
    """The stored integer, not a value rounded to a display scale."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=1234,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )

    assert (
        _course(await _portfolio(client, body), "CSC 121")["certified_minutes"] == 1234
    )


async def test_the_threshold_comes_from_settings_not_a_constant(
    client, db_session, monkeypatch: pytest.MonkeyPatch
):
    """The whole reason it is configuration: a pilot can lower it.

    The same tutor is eligible under one setting and not under the other, which
    is what a hardcoded threshold cannot do.
    """
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=600,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )

    _set_threshold(monkeypatch, 600)
    under_600 = _course(await _portfolio(client, body), "CSC 121")

    _set_threshold(monkeypatch, DEFAULT_REQUIRED_MINUTES)
    under_900 = _course(await _portfolio(client, body), "CSC 121")

    assert under_600["eligible"] is True
    assert under_900["eligible"] is False


@pytest.mark.parametrize("configured", [600, 1200, DEFAULT_REQUIRED_MINUTES])
async def test_the_wire_reports_the_configured_threshold(
    client, db_session, monkeypatch: pytest.MonkeyPatch, configured: int
):
    """The client renders the operator's number.

    Asserted for several settings rather than one, because a client that sent a
    constant would pass a test that only ever pinned the default.
    """
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _verified_competency(db_session, tutor, unit)
    _set_threshold(monkeypatch, configured)

    course = _course(await _portfolio(client, body), "CSC 121")
    assert course["required_minutes"] == configured
    assert course["remaining_minutes"] == configured
    assert course["required_sessions"] == DEFAULT_REQUIRED_SESSIONS
    assert Decimal(course["required_average_rating"]) == DEFAULT_MINIMUM_AVERAGE


async def test_the_session_and_rating_thresholds_come_from_settings(
    client, db_session, monkeypatch: pytest.MonkeyPatch
):
    """The same promise the minutes threshold makes, for the other two gates."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session)
    await _teach(
        db_session,
        tutor,
        unit,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=6,
        scores=(5, 5, 5, 5, 5, 5),
    )

    monkeypatch.setenv("CERTIFICATE_REQUIRED_SESSIONS", "6")
    monkeypatch.setenv("CERTIFICATE_MINIMUM_AVERAGE", "4.50")
    get_settings.cache_clear()
    lowered = _course(await _portfolio(client, body), "CSC 121")

    monkeypatch.setenv("CERTIFICATE_REQUIRED_SESSIONS", str(DEFAULT_REQUIRED_SESSIONS))
    monkeypatch.setenv("CERTIFICATE_MINIMUM_AVERAGE", str(DEFAULT_MINIMUM_AVERAGE))
    get_settings.cache_clear()
    restored = _course(await _portfolio(client, body), "CSC 121")

    assert lowered["required_sessions"] == 6
    assert lowered["eligible"] is True
    assert restored["required_sessions"] == DEFAULT_REQUIRED_SESSIONS
    assert restored["eligible"] is False


def test_the_shipped_defaults_are_fifteen_hours_ten_sessions_and_410() -> None:
    """The numbers in the docs are the numbers the code ships with."""
    settings = Settings(_env_file=None)  # type: ignore[call-arg]

    assert settings.certificate_required_minutes == DEFAULT_REQUIRED_MINUTES
    assert settings.certificate_required_sessions == DEFAULT_REQUIRED_SESSIONS
    assert settings.certificate_minimum_average == DEFAULT_MINIMUM_AVERAGE


def test_a_zero_minutes_threshold_is_refused_at_startup() -> None:
    """Otherwise the progress division is a division by zero on every request."""
    with pytest.raises(ValueError):
        Settings(_env_file=None, certificate_required_minutes=0)  # type: ignore[call-arg]


def test_a_zero_session_threshold_is_refused_at_startup() -> None:
    """A zero would make the certificate's session record vacuous."""
    with pytest.raises(ValueError):
        Settings(_env_file=None, certificate_required_sessions=0)  # type: ignore[call-arg]


# --- which courses are in the portfolio -------------------------------------


async def test_a_verified_course_with_no_sessions_is_on_the_path(client, db_session):
    """A new tutor sees the target they are working towards, not an empty list."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session, code="BIT 221", name="Operating Systems")
    await _verified_competency(db_session, tutor, unit)

    course = _course(await _portfolio(client, body), "BIT 221")
    assert course["certified_minutes"] == 0
    assert course["completed_sessions"] == 0
    assert course["eligible"] is False
    assert course["progress"] == 0.0


async def test_completed_sessions_appear_even_without_a_live_competency(
    client, db_session
):
    """The teaching happened. A later status change must not erase the evidence."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session, code="BIT 223", name="Computer Networks")
    await _teach(db_session, tutor, unit, minutes=120, sessions=2, scores=(5, 5))

    course = _course(await _portfolio(client, body), "BIT 223")
    assert course["certified_minutes"] == 120
    assert course["completed_sessions"] == 2


async def test_a_pending_claim_with_no_sessions_is_not_a_certificate(
    client, db_session
):
    """A claim is not evidence. Only verification or teaching puts a course here."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session, code="BIT 225", name="Artificial Intelligence")
    scale = GradingScale(
        name=f"Scale {uuid.uuid4().hex[:8]}",
        max_points=Decimal("5"),
        competency_min_points=Decimal("4"),
    )
    grade = Grade(
        label="A",
        grade_points=Decimal("5"),
        max_points=Decimal("5"),
        grading_scale=scale,
    )
    db_session.add_all([scale, grade])
    await db_session.flush()
    db_session.add(
        Competency(
            user_id=tutor.id,
            course_unit_id=unit.id,
            grade_id=grade.id,
            status=CompetencyStatus.PENDING,
            source=VerificationSource.TRANSCRIPT,
        )
    )
    await db_session.commit()

    assert (await _portfolio(client, body))["courses"] == []


async def test_certificates_are_not_pooled_across_courses(client, db_session):
    """The rule this feature exists for.

    Nine hundred minutes in one course and six hundred in another is not fifteen
    hundred minutes towards one certificate: the first course earns its own and
    the second is still six hundred minutes into its own.
    """
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    finished = await _unit(db_session, code="BIT 221", name="Operating Systems")
    partial = await _unit(db_session, code="BIT 223", name="Computer Networks")
    await _teach(
        db_session,
        tutor,
        finished,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )
    await _teach(
        db_session,
        tutor,
        partial,
        minutes=600,
        sessions=5,
        scores=(5, 5, 5, 5, 5),
    )

    payload = await _portfolio(client, body)
    assert len(payload["courses"]) == 2
    # Earned first, then closest to earned.
    assert payload["courses"][0]["course_unit_code"] == "BIT 221"
    assert payload["courses"][0]["eligible"] is True
    assert payload["courses"][1]["course_unit_code"] == "BIT 223"
    assert payload["courses"][1]["certified_minutes"] == 600
    assert payload["courses"][1]["eligible"] is False
    assert payload["courses"][1]["remaining_minutes"] == 300


async def test_ratings_count_only_for_the_course_they_were_left_in(client, db_session):
    """Ten ratings in one course must not satisfy the rating gate in another."""
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    rated = await _unit(db_session, code="BIT 221", name="Operating Systems")
    unrated = await _unit(db_session, code="BIT 223", name="Computer Networks")
    await _teach(
        db_session,
        tutor,
        rated,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
        scores=(4,) * 9 + (5,),
    )
    await _teach(
        db_session,
        tutor,
        unrated,
        minutes=DEFAULT_REQUIRED_MINUTES,
        sessions=DEFAULT_REQUIRED_SESSIONS,
    )

    payload = await _portfolio(client, body)
    assert _course(payload, "BIT 221")["rating_count"] == DEFAULT_REQUIRED_SESSIONS
    assert _course(payload, "BIT 223")["rating_count"] == 0
    assert _course(payload, "BIT 223")["rating_met"] is False


# --- a user with no tutor profile -------------------------------------------


async def test_a_user_with_no_tutor_profile_gets_a_real_answer(client, db_session):
    """A student is not a tutor yet, and that is a state, not an error.

    A 404 here would put a signed-in student's screen into a failure over
    something they did not do, and a `null` body would be a silence where the
    answer is known.
    """
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    payload = await _portfolio(client, body)
    assert payload["has_tutor_profile"] is False
    assert payload["courses"] == []


async def test_reading_certificates_creates_no_profile(client, db_session):
    """A `GET` that minted a profile would hand every student a standing."""
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    await _portfolio(client, body)

    profiles = await db_session.scalar(select(func.count()).select_from(TutorProfile))
    assert profiles == 0


async def test_a_tutor_with_no_course_yet_is_on_the_path(client, db_session):
    """Distinct from having no profile: a profile and no course evidence yet."""
    body, _tutor_user = await _tutor(client, db_session, "tutor@mak.ac.ug")

    payload = await _portfolio(client, body)
    assert payload["has_tutor_profile"] is True
    assert payload["courses"] == []


# --- only ever your own ------------------------------------------------------


async def test_the_caller_reads_their_own_courses(client, db_session):
    body, mine = await _tutor(client, db_session, "mine@mak.ac.ug")
    my_unit = await _unit(db_session, code="BIT 221", name="Operating Systems")
    await _teach(db_session, mine, my_unit, minutes=1200, sessions=10, scores=(5,) * 10)

    _their_body, theirs = await _tutor(client, db_session, "theirs@mak.ac.ug")
    their_unit = await _unit(db_session, code="BIT 223", name="Computer Networks")
    await _teach(
        db_session, theirs, their_unit, minutes=300, sessions=5, scores=(5,) * 5
    )

    mine_payload = await _portfolio(client, body)
    assert [course["course_unit_code"] for course in mine_payload["courses"]] == [
        "BIT 221"
    ]
    assert mine_payload["courses"][0]["certified_minutes"] == 1200


async def test_another_tutors_courses_cannot_be_asked_for(client, db_session):
    """The route has no subject, so there is nothing to point at someone else."""
    body, _mine = await _tutor(client, db_session, "mine@mak.ac.ug")
    other_body, other = await _tutor(client, db_session, "theirs@mak.ac.ug")
    their_unit = await _unit(db_session, code="BIT 223", name="Computer Networks")
    await _teach(db_session, other, their_unit, minutes=300, sessions=5)

    mine = await client.get(
        "/v1/incentives/certificate",
        params={"user_id": str(other.public_id)},
        headers=_bearer(body),
    )
    theirs = await client.get("/v1/incentives/certificate", headers=_bearer(other_body))

    assert mine.json()["courses"] == []
    assert theirs.json()["courses"][0]["course_unit_code"] == "BIT 223"


async def test_certificates_require_a_token(client, db_session):
    """A certificate total is a tutor's own record, not public standing."""
    await _tutor(client, db_session, "tutor@mak.ac.ug")

    response = await client.get("/v1/incentives/certificate")

    assert response.status_code == 401
    assert response.headers["content-type"].startswith("application/problem+json")


# --- which sessions counted --------------------------------------------------


async def test_a_completed_session_contributes_its_minutes(db_session):
    tutor_user = User(
        email="tutor@mak.ac.ug", password_hash="hashed-password", full_name="Tutor"
    )
    db_session.add(tutor_user)
    await db_session.flush()
    session = await _session(
        db_session,
        tutor_user,
        status=SessionStatus.COMPLETED,
        duration_minutes=60,
        started_at=datetime.now(UTC) - timedelta(hours=1),
        ended_at=datetime.now(UTC),
    )

    await rating_service.record_completion(db_session, session)

    summary = await incentive_service.get_certificate_eligibility(
        db_session, tutor_user
    )
    assert summary.certified_minutes == 60
    assert summary.eligible is False


@pytest.mark.parametrize(
    "status",
    [
        SessionStatus.SCHEDULED,
        SessionStatus.IN_PROGRESS,
        SessionStatus.CANCELLED,
    ],
)
async def test_a_session_that_did_not_complete_contributes_nothing(
    db_session, status: SessionStatus
):
    """Whatever duration it was booked with, and whoever cancelled it."""
    tutor_user = User(
        email="tutor@mak.ac.ug", password_hash="hashed-password", full_name="Tutor"
    )
    db_session.add(tutor_user)
    await db_session.flush()
    session = await _session(db_session, tutor_user, status=status, duration_minutes=90)

    await rating_service.record_completion(db_session, session)

    summary = await incentive_service.get_certificate_eligibility(
        db_session, tutor_user
    )
    assert summary.certified_minutes == 0


async def test_a_negative_duration_contributes_nothing(db_session):
    """`max(duration_minutes, 0)` is the backstop, and it is load-bearing.

    The schema refuses a negative duration, so this can only arrive through a
    data fix or a migration. Hours are the tutor's record of what they taught: a
    total that falls because a row was repaired is not defensible.
    """
    tutor_user = User(
        email="tutor@mak.ac.ug", password_hash="hashed-password", full_name="Tutor"
    )
    db_session.add(tutor_user)
    await db_session.flush()
    session = Session(
        tutee_id=uuid.uuid4(),
        tutor_id=tutor_user.id,
        course_unit_id=uuid.uuid4(),
        topic="Quick sort",
        status=SessionStatus.COMPLETED,
        started_at=datetime.now(UTC) - timedelta(hours=1),
        ended_at=datetime.now(UTC),
        duration_minutes=-30,
    )

    await rating_service.record_completion(db_session, session)

    summary = await incentive_service.get_certificate_eligibility(
        db_session, tutor_user
    )
    assert summary.certified_minutes == 0


async def test_the_session_lifecycle_is_what_banks_the_minutes(client, db_session):
    """The path a client takes, not a call to the increment.

    The tutor starts at zero, runs a session from `in_progress` to `completed`,
    and the ninety minutes it took are what the endpoint afterwards reports for
    that course.
    """
    body, tutor = await _tutor(client, db_session, "tutor@mak.ac.ug")
    unit = await _unit(db_session, code="BIT 221", name="Operating Systems")
    session = await _session(
        db_session,
        tutor,
        status=SessionStatus.IN_PROGRESS,
        duration_minutes=0,
        started_at=datetime.now(UTC) - timedelta(minutes=90),
        unit=unit,
    )

    tutee = await db_session.scalar(select(User).where(User.id == session.tutee_id))
    assert tutee is not None
    await session_service.finish(db_session, tutor, session.public_id)
    completed = await session_service.finish(db_session, tutee, session.public_id)
    assert completed.duration_minutes == 90

    course = _course(await _portfolio(client, body), "BIT 221")
    assert course["certified_minutes"] == 90
    assert course["eligible"] is False

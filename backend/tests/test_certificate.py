"""Certificate eligibility: the threshold, and whose hours it is.

Two things are being pinned here, and the second is the reason the file goes
through the real router.

The boundary is the product rule. The threshold is a configured number of
minutes, eligibility is `certified_minutes >= required_minutes`, and a tutor
exactly on the threshold is eligible while one minute short is not. That is one
`>=`, and it is the kind of rule a later refactor turns into a `>` or a rounded
comparison without anything failing.

The wire contract is the rest. A service that computes the right answer behind a
route wired without an auth guard, or pointed at a schema that drops the
configured threshold, passes every service-level test and shows every tutor the
same number.

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
from app.models.course_unit import CourseUnit, Subject, University
from app.models.enums import SessionStatus, TutorStanding
from app.models.session import Session
from app.models.tutor_profile import TutorProfile
from app.models.user import User
from app.services import incentive_service, rating_service, session_service

GOOD_PASSWORD = "correct horse battery staple"

#: The defaults the pilot ships with, stated here so the boundary tests below say
#: "2400 and 2399" rather than "the configured value and one less".
DEFAULT_REQUIRED_MINUTES = 2400
DEFAULT_REQUIRED_SESSIONS = 10
DEFAULT_MINIMUM_AVERAGE = Decimal("4.10")


@pytest.fixture(autouse=True)
def _threshold_from_the_environment(monkeypatch: pytest.MonkeyPatch):
    """Pin all three thresholds to their defaults for every test in this file.

    `get_settings` reads the environment and a local `.env`, so a developer's own
    `CERTIFICATE_REQUIRED_MINUTES` would otherwise decide whether a test that
    states 2400 and 2399 passed. The cache is cleared on the way out as well as
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


# --- fixtures ----------------------------------------------------------------


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


async def _tutor(
    client,
    db_session,
    email: str,
    *,
    certified_minutes: int,
    completed_sessions: int = 28,
    rating_count: int | None = None,
    rating_total: Decimal | None = None,
) -> tuple[dict, User]:
    """An account with the stored totals a tutor of that standing would have.

    The profile row is written directly rather than earned through a verified
    competency and twenty-eight completed sessions. These tests are about the
    read, and the accrual is tested separately against the code that does it.

    The defaults describe a tutor who meets the session and rating conditions, so
    a test that is about the *minutes* boundary still reaches an eligible answer
    and fails only for the minute it is testing. Tests about the other two gates
    pass the count or total they want short.
    """
    body, user = await _account(client, db_session, email)
    if rating_count is None:
        rating_count = completed_sessions
    if rating_total is None:
        rating_total = Decimal(rating_count) * Decimal("5")
    db_session.add(
        TutorProfile(
            user_id=user.id,
            standing=TutorStanding.PROBATIONARY,
            completed_sessions=completed_sessions,
            certified_minutes=certified_minutes,
            rating_total=rating_total,
            rating_count=rating_count,
        )
    )
    await db_session.commit()
    return body, user


async def _session(
    db_session,
    tutor: User,
    *,
    status: SessionStatus,
    duration_minutes: int,
    started_at: datetime | None = None,
    ended_at: datetime | None = None,
) -> Session:
    """One session row, with the university a session's unit has to hang off."""
    university = University(name="Makerere University")
    subject = Subject(name="Computer Science")
    unit = CourseUnit(
        code="CSC 121",
        name="Algorithms",
        subject=subject,
        university=university,
    )
    student = User(
        email="student@mak.ac.ug",
        password_hash="hashed-password",
        full_name="Student Example",
    )
    db_session.add_all([university, subject, unit, student])
    await db_session.flush()
    # The mutual check-in constraints are part of the schema now, so a row that
    # claims to be live has to carry both arrivals and a completed row both
    # departures. Tests that are about the certificate read, not attendance,
    # still need rows the schema accepts.
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


# --- the threshold -----------------------------------------------------------


async def test_exactly_the_required_minutes_is_eligible(client, db_session):
    """The boundary, from the inside. A threshold met is a threshold met."""
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=2400
    )

    response = await client.get("/v1/incentives/certificate", headers=_bearer(body))

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["eligible"] is True
    assert payload["certified_minutes"] == 2400
    assert payload["remaining_minutes"] == 0


async def test_one_minute_short_is_not_eligible(client, db_session):
    """The boundary, from the outside. This is the case that must not round."""
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=2399
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is False
    assert payload["remaining_minutes"] == 1
    # Not one hour of progress, and not a rounded 40: a bar built from either
    # would tell a tutor one minute from the threshold that they are done.
    assert payload["progress"] == pytest.approx(2399 / 2400)


async def test_well_past_the_threshold_is_eligible_and_capped(client, db_session):
    """A tutor who taught twice the requirement is complete, not overflowing."""
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=4800
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is True
    assert payload["progress"] == 1.0
    assert payload["remaining_minutes"] == 0


async def test_hours_alone_do_not_earn_a_certificate(client, db_session):
    """The bug the session gate exists for.

    A tutor with four very long sessions can pass the 40-hour threshold while
    having taught only four times. That is volume, not a sustained record, and
    the certificate must not call it one.
    """
    body, _user = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        certified_minutes=4800,
        completed_sessions=4,
        rating_count=4,
        rating_total=Decimal("20"),
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is False
    assert payload["minutes_met"] is True
    assert payload["sessions_met"] is False
    # Four ratings is also short of the ten-rating condition; the point here is
    # that the completed sessions and the ratings are the same four.
    assert payload["rating_met"] is False
    assert payload["remaining_sessions"] == DEFAULT_REQUIRED_SESSIONS - 4
    # The bar is drawn from the limiting requirement, not from the hours that
    # happened to be complete.
    assert payload["progress"] == pytest.approx(4 / DEFAULT_REQUIRED_SESSIONS)


async def test_enough_sessions_but_too_few_ratings_is_not_eligible(client, db_session):
    """A completed session is not rated evidence until the student rates it."""
    body, _user = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        certified_minutes=4800,
        completed_sessions=DEFAULT_REQUIRED_SESSIONS,
        rating_count=3,
        rating_total=Decimal("15"),
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is False
    assert payload["sessions_met"] is True
    assert payload["rating_met"] is False
    assert payload["rating_count"] == 3
    assert payload["progress"] == pytest.approx(3 / DEFAULT_REQUIRED_SESSIONS)


async def test_enough_ratings_but_a_low_average_is_not_eligible(client, db_session):
    """Maintaining the rating bar is the second half of the rating condition."""
    body, _user = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        certified_minutes=4800,
        completed_sessions=DEFAULT_REQUIRED_SESSIONS,
        rating_count=DEFAULT_REQUIRED_SESSIONS,
        rating_total=Decimal("35.00"),  # 3.50 average
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is False
    assert payload["sessions_met"] is True
    assert payload["rating_met"] is False
    assert payload["average_rating"] == "3.50"
    assert payload["progress"] == pytest.approx(3.5 / 4.1)


async def test_exactly_the_bar_on_all_three_conditions_is_eligible(client, db_session):
    """The boundary is inclusive on every requirement, not just the minutes."""
    body, _user = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        certified_minutes=DEFAULT_REQUIRED_MINUTES,
        completed_sessions=DEFAULT_REQUIRED_SESSIONS,
        rating_count=DEFAULT_REQUIRED_SESSIONS,
        rating_total=DEFAULT_MINIMUM_AVERAGE * DEFAULT_REQUIRED_SESSIONS,
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is True
    assert payload["minutes_met"] is True
    assert payload["sessions_met"] is True
    assert payload["rating_met"] is True
    assert payload["progress"] == 1.0


async def test_minutes_are_sent_exactly_as_stored(client, db_session):
    """The stored integer, not a value rounded to a display scale.

    `certified_minutes` is an `Integer` column and the verdict is a `>=` against
    it, so a second number on the wire that the verdict was not computed from
    would be a number the tutor can check and find wrong.
    """
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=1234
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["certified_minutes"] == 1234


async def test_the_threshold_comes_from_settings_not_a_constant(
    client, db_session, monkeypatch: pytest.MonkeyPatch
):
    """The whole reason it is configuration: a pilot can lower it.

    The same tutor is eligible under one setting and not under the other, which
    is what a hardcoded 2400 cannot do.
    """
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=600
    )

    _set_threshold(monkeypatch, 600)
    under_600 = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    _set_threshold(monkeypatch, DEFAULT_REQUIRED_MINUTES)
    under_2400 = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert under_600["eligible"] is True
    assert under_2400["eligible"] is False


@pytest.mark.parametrize("configured", [600, 1200, DEFAULT_REQUIRED_MINUTES])
async def test_the_wire_reports_the_configured_threshold(
    client, db_session, monkeypatch: pytest.MonkeyPatch, configured: int
):
    """The client renders the operator's number.

    Asserted for several settings rather than one, because a client that sent a
    constant would pass a test that only ever pinned the default.
    """
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=0
    )
    _set_threshold(monkeypatch, configured)

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["required_minutes"] == configured
    assert payload["remaining_minutes"] == configured
    assert payload["required_sessions"] == DEFAULT_REQUIRED_SESSIONS
    assert Decimal(payload["required_average_rating"]) == DEFAULT_MINIMUM_AVERAGE


async def test_the_session_and_rating_thresholds_come_from_settings(
    client, db_session, monkeypatch: pytest.MonkeyPatch
):
    """The same promise the minutes threshold makes, for the other two gates.

    A pilot with a small cohort has to be able to lower the session count without
    a deploy, and a stricter one has to be able to raise it.
    """
    body, _user = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        certified_minutes=4800,
        completed_sessions=6,
        rating_count=6,
        rating_total=Decimal("30.00"),
    )

    monkeypatch.setenv("CERTIFICATE_REQUIRED_SESSIONS", "6")
    monkeypatch.setenv("CERTIFICATE_MINIMUM_AVERAGE", "4.50")
    get_settings.cache_clear()
    lowered = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    monkeypatch.setenv("CERTIFICATE_REQUIRED_SESSIONS", str(DEFAULT_REQUIRED_SESSIONS))
    monkeypatch.setenv("CERTIFICATE_MINIMUM_AVERAGE", str(DEFAULT_MINIMUM_AVERAGE))
    get_settings.cache_clear()
    restored = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert lowered["required_sessions"] == 6
    assert lowered["eligible"] is True
    assert restored["required_sessions"] == DEFAULT_REQUIRED_SESSIONS
    assert restored["eligible"] is False


def test_the_shipped_defaults_are_forty_hours_ten_sessions_and_410() -> None:
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
    """A zero would make the certificate's session record vacuous.

    The division in the progress helper is also a guard, but the setting is
    refused for the product reason: "earned over zero sessions" is not a thing
    the certificate is supposed to mean.
    """
    with pytest.raises(ValueError):
        Settings(_env_file=None, certificate_required_sessions=0)  # type: ignore[call-arg]


# --- a user with no tutor profile -------------------------------------------


async def test_a_user_with_no_tutor_profile_gets_a_real_answer(client, db_session):
    """A student is not a tutor yet, and that is a state, not an error.

    A 404 here would put a signed-in student's screen into a failure over
    something they did not do, and a `null` body would be a silence where the
    answer is known.
    """
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    response = await client.get("/v1/incentives/certificate", headers=_bearer(body))

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["has_tutor_profile"] is False
    assert payload["eligible"] is False
    assert payload["certified_minutes"] == 0
    assert payload["remaining_minutes"] == payload["required_minutes"]
    assert payload["completed_sessions"] == 0
    assert payload["remaining_sessions"] == payload["required_sessions"]
    assert payload["rating_count"] == 0
    assert payload["average_rating"] is None
    assert payload["minutes_met"] is False
    assert payload["sessions_met"] is False
    assert payload["rating_met"] is False
    assert payload["progress"] == 0.0


async def test_reading_eligibility_creates_no_profile(client, db_session):
    """The regression `rating_service` was fixed for, on this read too.

    A `GET` that minted a profile would hand every signed-in student a standing
    and a certificate total of zero merely by opening the screen.
    """
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    await client.get("/v1/incentives/certificate", headers=_bearer(body))

    profiles = await db_session.scalar(select(func.count()).select_from(TutorProfile))
    assert profiles == 0


async def test_a_tutor_with_no_minutes_yet_is_on_the_path(client, db_session):
    """Distinct from having no profile: a profile, no hours, and a bar to fill."""
    body, _user = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=0
    )

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["has_tutor_profile"] is True
    assert payload["eligible"] is False


# --- only ever your own ------------------------------------------------------


async def test_the_caller_reads_their_own_totals(client, db_session):
    body, _mine = await _tutor(
        client, db_session, "mine@mak.ac.ug", certified_minutes=2400
    )
    await _tutor(client, db_session, "theirs@mak.ac.ug", certified_minutes=0)

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["eligible"] is True
    assert payload["certified_minutes"] == 2400


async def test_another_tutors_totals_cannot_be_asked_for(client, db_session):
    """The route has no subject, so there is nothing to point at someone else.

    A query parameter naming another account is ignored rather than refused,
    because the answer it produces is already the caller's own: there is no
    version of this request that reaches anyone else's hours.
    """
    body, _mine = await _tutor(
        client, db_session, "mine@mak.ac.ug", certified_minutes=2400
    )
    other_body, other_user = await _tutor(
        client, db_session, "theirs@mak.ac.ug", certified_minutes=0
    )

    mine = await client.get(
        "/v1/incentives/certificate",
        params={"user_id": str(other_user.public_id)},
        headers=_bearer(body),
    )
    theirs = await client.get("/v1/incentives/certificate", headers=_bearer(other_body))

    assert mine.json()["certified_minutes"] == 2400
    # The two accounts really are different, so the assertion above is about
    # whose minutes were served and not about two identical responses.
    assert theirs.json()["certified_minutes"] == 0


async def test_eligibility_requires_a_token(client, db_session):
    """A certificate total is a tutor's own record, not public standing."""
    await _tutor(client, db_session, "tutor@mak.ac.ug", certified_minutes=2400)

    response = await client.get("/v1/incentives/certificate")

    assert response.status_code == 401
    assert response.headers["content-type"].startswith("application/problem+json")


# --- which sessions counted --------------------------------------------------


async def test_a_completed_session_contributes_its_minutes(db_session):
    tutor = User(
        email="tutor@mak.ac.ug", password_hash="hashed-password", full_name="Tutor"
    )
    db_session.add(tutor)
    await db_session.flush()
    session = await _session(
        db_session,
        tutor,
        status=SessionStatus.COMPLETED,
        duration_minutes=60,
        started_at=datetime.now(UTC) - timedelta(hours=1),
        ended_at=datetime.now(UTC),
    )

    await rating_service.record_completion(db_session, session)

    eligibility = await incentive_service.get_certificate_eligibility(db_session, tutor)
    assert eligibility.certified_minutes == 60
    assert eligibility.eligible is False


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
    """Whatever duration it was booked with, and whoever cancelled it.

    A cancelled session keeps the length it was created with, so reading the
    column would bank hours for teaching that did not happen. That the
    increment is guarded by the status is the rule under test.
    """
    tutor = User(
        email="tutor@mak.ac.ug", password_hash="hashed-password", full_name="Tutor"
    )
    db_session.add(tutor)
    await db_session.flush()
    session = await _session(db_session, tutor, status=status, duration_minutes=90)

    await rating_service.record_completion(db_session, session)

    eligibility = await incentive_service.get_certificate_eligibility(db_session, tutor)
    assert eligibility.certified_minutes == 0


async def test_a_negative_duration_contributes_nothing(db_session):
    """`max(duration_minutes, 0)` is the backstop, and it is load-bearing.

    The schema and the CHECK constraint both refuse a negative duration, so this
    cannot arrive through the API. It can arrive through a data fix or a
    migration, and hours are the tutor's record of what they taught: a total
    that falls because a row was repaired is not defensible.

    Never added to the session, because the column would refuse the value and
    the point is the increment's arithmetic rather than a row that could be
    written.
    """
    tutor = User(
        email="tutor@mak.ac.ug", password_hash="hashed-password", full_name="Tutor"
    )
    db_session.add(tutor)
    await db_session.flush()
    session = Session(
        tutee_id=uuid.uuid4(),
        tutor_id=tutor.id,
        course_unit_id=uuid.uuid4(),
        topic="Quick sort",
        status=SessionStatus.COMPLETED,
        started_at=datetime.now(UTC) - timedelta(hours=1),
        ended_at=datetime.now(UTC),
        duration_minutes=-30,
    )

    await rating_service.record_completion(db_session, session)

    eligibility = await incentive_service.get_certificate_eligibility(db_session, tutor)
    assert eligibility.certified_minutes == 0


async def test_the_session_lifecycle_is_what_banks_the_minutes(client, db_session):
    """The path a client takes, not a call to the increment.

    A test of `record_completion` on its own passes even if nothing in the
    service ever calls it, and a certificate nobody earns is worse than one that
    is never displayed. The tutor starts at zero, runs a session from
    `in_progress` to `completed`, and the ninety minutes it took are what the
    endpoint afterwards reports.
    """
    body, tutor = await _tutor(
        client, db_session, "tutor@mak.ac.ug", certified_minutes=0
    )
    session = await _session(
        db_session,
        tutor,
        status=SessionStatus.IN_PROGRESS,
        duration_minutes=0,
        started_at=datetime.now(UTC) - timedelta(minutes=90),
    )

    tutee = await db_session.scalar(select(User).where(User.id == session.tutee_id))
    assert tutee is not None
    await session_service.finish(db_session, tutor, session.public_id)
    completed = await session_service.finish(db_session, tutee, session.public_id)
    assert completed.duration_minutes == 90

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["certified_minutes"] == 90
    assert payload["eligible"] is False

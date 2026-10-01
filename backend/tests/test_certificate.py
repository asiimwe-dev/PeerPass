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
from app.schemas.session import SessionTransitionRequest
from app.services import incentive_service, rating_service, session_service

GOOD_PASSWORD = "correct horse battery staple"

#: The default the pilot ships with, stated here so the boundary tests below say
#: "2400 and 2399" rather than "the configured value and one less".
DEFAULT_REQUIRED_MINUTES = 2400


@pytest.fixture(autouse=True)
def _threshold_from_the_environment(monkeypatch: pytest.MonkeyPatch):
    """Pin the threshold to its default for every test in this file.

    `get_settings` reads the environment and a local `.env`, so a developer's own
    `CERTIFICATE_REQUIRED_MINUTES` would otherwise decide whether a test that
    states 2400 and 2399 passed. The cache is cleared on the way out as well as
    on the way in, because the settings object is process-wide and a threshold
    left behind here would answer the rest of the suite.
    """
    monkeypatch.setenv("CERTIFICATE_REQUIRED_MINUTES", str(DEFAULT_REQUIRED_MINUTES))
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
    client, db_session, email: str, *, certified_minutes: int
) -> tuple[dict, User]:
    """An account with the stored hours a tutor of that standing would have.

    The profile row is written directly rather than earned through a verified
    competency and twenty-eight completed sessions. These tests are about the
    read, and the accrual is tested separately against the code that does it.
    """
    body, user = await _account(client, db_session, email)
    db_session.add(
        TutorProfile(
            user_id=user.id,
            standing=TutorStanding.PROBATIONARY,
            completed_sessions=28,
            certified_minutes=certified_minutes,
            rating_total=Decimal("0"),
            rating_count=0,
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
    session = Session(
        tutee_id=student.id,
        tutor_id=tutor.id,
        course_unit_id=unit.id,
        topic="Quick sort",
        status=status,
        started_at=started_at,
        ended_at=ended_at,
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


def test_the_shipped_default_is_forty_hours() -> None:
    """The number in the docs is the number the code ships with."""
    settings = Settings(_env_file=None)  # type: ignore[call-arg]

    assert settings.certificate_required_minutes == DEFAULT_REQUIRED_MINUTES


def test_a_zero_threshold_is_refused_at_startup() -> None:
    """Otherwise the progress division is a division by zero on every request."""
    with pytest.raises(ValueError):
        Settings(_env_file=None, certificate_required_minutes=0)  # type: ignore[call-arg]


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

    completed = await session_service.transition_session(
        db_session,
        tutor,
        session.public_id,
        SessionTransitionRequest(status=SessionStatus.COMPLETED),
    )
    assert completed.duration_minutes == 90

    payload = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert payload["certified_minutes"] == 90
    assert payload["eligible"] is False

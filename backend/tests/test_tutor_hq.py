"""The tutor's own HQ: standing, the two promotion conditions, and availability.

Two kinds of rule are pinned here and neither substitutes for the other.

The promotion rule has two halves, not one: enough rated sessions *and* an
average at or above the bar. A screen that showed only the session count would
tell a tutor they were finished while their average was still short, which is
the mistake this endpoint exists to make impossible.

The wire contract is the rest. These tests go through the real router with real
access tokens, because a service that computes the right answer behind a route
wired without an auth guard, or one shadowed by `GET /v1/tutors/{user_id}`,
passes every service-level test and ships a screen that cannot load.

The last group is the regression that bit the discovery rail: no `GET` may
create a `TutorProfile`. A dashboard that minted one would hand every signed-in
student a `probationary` standing merely by opening the screen.
"""

from decimal import Decimal

import pytest
from sqlalchemy import func, select

from app.core.config import get_settings
from app.models.enums import TutorStanding
from app.models.tutor_profile import TutorProfile
from app.models.user import User

GOOD_PASSWORD = "correct horse battery staple"


# --- wire helpers ----------------------------------------------------------


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
    standing: TutorStanding = TutorStanding.PROBATIONARY,
    completed_sessions: int = 0,
    certified_minutes: int = 0,
    rating_total: Decimal = Decimal("0"),
    rating_count: int = 0,
    accepting_requests: bool = True,
) -> tuple[dict, User, TutorProfile]:
    """An account with a stored profile, written directly.

    These tests are about the read. Standing is earned through ratings and
    verified competencies elsewhere, and a fixture that recreated that path would
    test the rating service before it tested this endpoint.
    """
    body, user = await _account(client, db_session, email)
    profile = TutorProfile(
        user_id=user.id,
        standing=standing,
        completed_sessions=completed_sessions,
        certified_minutes=certified_minutes,
        rating_total=rating_total,
        rating_count=rating_count,
        accepting_requests=accepting_requests,
    )
    db_session.add(profile)
    await db_session.commit()
    return body, user, profile


# --- the student's answer --------------------------------------------------


async def test_a_student_is_told_they_are_not_a_tutor_yet(client, db_session):
    """A missing profile is a real state, not a 404 over a screen they opened."""
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    response = await client.get("/v1/tutors/me", headers=_bearer(body))

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["has_tutor_profile"] is False
    assert payload["standing"] is None
    assert payload["accepting_requests"] is None
    assert payload["completed_sessions"] == 0
    assert payload["rating_count"] == 0
    assert payload["average_rating"] is None
    assert payload["promotion"]["verified"] is False
    assert payload["promotion"]["rated_sessions"] == 0
    assert payload["promotion"]["sessions_remaining"] == 3
    assert payload["promotion"]["meets_average"] is False
    assert payload["promotion"]["progress"] == 0.0


async def test_reading_the_hq_never_creates_a_profile(client, db_session):
    """A dashboard open is not a reason to mint a standing."""
    body, user = await _account(client, db_session, "student@mak.ac.ug")
    before = await db_session.scalar(select(func.count()).select_from(TutorProfile))

    response = await client.get("/v1/tutors/me", headers=_bearer(body))

    assert response.status_code == 200, response.text
    after = await db_session.scalar(select(func.count()).select_from(TutorProfile))
    assert after == before
    assert user.id is not None


async def test_the_hq_requires_an_access_token(client):
    response = await client.get("/v1/tutors/me")
    assert response.status_code == 401, response.text


async def test_me_is_not_shadowed_by_the_tutor_detail_route(client, db_session):
    """A literal `me` must not be read as a public id.

    `GET /v1/tutors/{user_id}` is declared below this route for exactly this
    reason. If the order ever flips, this answers 422 and the whole screen dies.
    """
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    response = await client.get("/v1/tutors/me", headers=_bearer(body))

    assert response.status_code == 200, response.text


# --- the promotion rule ----------------------------------------------------


async def test_a_new_tutor_sees_both_conditions_as_outstanding(client, db_session):
    """One rated session is not three, even with a perfect average."""
    body, _user, _profile = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        completed_sessions=4,
        rating_total=Decimal("5.00"),
        rating_count=1,
    )

    payload = (await client.get("/v1/tutors/me", headers=_bearer(body))).json()

    promotion = payload["promotion"]
    assert promotion["verified"] is False
    assert promotion["rated_sessions"] == 1
    assert promotion["sessions_required"] == 3
    assert promotion["sessions_remaining"] == 2
    assert promotion["meets_average"] is True
    # One third of the evidence, from the rating count rather than the four
    # completed sessions in the payload.
    assert promotion["progress"] == pytest.approx(1 / 3)


async def test_promotion_counts_ratings_not_completed_sessions(client, db_session):
    """A completed session waits on a rating, and must not advance the ring.

    Completion and rating are separate actions, so the two counts are allowed to
    disagree. The promotion rule reads the rating count; showing the completed
    count here would show a full ring the rule would not act on.
    """
    body, _user, _profile = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        completed_sessions=10,
        rating_total=Decimal("25.00"),
        rating_count=2,
    )

    payload = (await client.get("/v1/tutors/me", headers=_bearer(body))).json()

    assert payload["completed_sessions"] == 10
    assert payload["promotion"]["rated_sessions"] == 2
    assert payload["promotion"]["sessions_remaining"] == 1
    assert payload["promotion"]["progress"] == pytest.approx(2 / 3)


@pytest.mark.parametrize(
    ("rating_total", "meets_average"),
    [
        # Exactly on the bar is in, one cent below is out. The rule is an
        # equality test on the exact mean, not on a rounded display value.
        (Decimal("12.30"), True),
        (Decimal("12.29"), False),
    ],
)
async def test_the_average_boundary_is_exact(
    client, db_session, rating_total: Decimal, meets_average: bool
):
    body, _user, _profile = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        completed_sessions=3,
        rating_total=rating_total,
        rating_count=3,
    )

    payload = (await client.get("/v1/tutors/me", headers=_bearer(body))).json()

    assert payload["promotion"]["meets_average"] is meets_average
    assert payload["promotion"]["minimum_average"] == "4.10"


async def test_a_verified_tutor_reads_as_finished(client, db_session):
    """Verification is the stored standing, not a re-run of the thresholds."""
    body, _user, _profile = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        standing=TutorStanding.VERIFIED,
        completed_sessions=12,
        certified_minutes=600,
        rating_total=Decimal("44.00"),
        rating_count=10,
    )

    payload = (await client.get("/v1/tutors/me", headers=_bearer(body))).json()

    assert payload["standing"] == "verified"
    assert payload["promotion"]["verified"] is True
    assert payload["promotion"]["sessions_remaining"] == 0
    assert payload["promotion"]["progress"] == 1.0
    assert payload["average_rating"] == "4.40"


async def test_a_verified_tutor_keeps_the_ring_even_below_the_promotion_bar(
    client, db_session
):
    """A verified tutor is not demoted by one slightly lower average.

    The rating service retains the badge until the explicit demotion bar is
    crossed. Recomputing the promotion bar here would show a tutor as un-verified
    while the API still offers them as verified.
    """
    body, _user, _profile = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        standing=TutorStanding.VERIFIED,
        completed_sessions=10,
        rating_total=Decimal("40.00"),
        rating_count=10,
    )

    payload = (await client.get("/v1/tutors/me", headers=_bearer(body))).json()

    assert payload["promotion"]["verified"] is True
    assert payload["promotion"]["meets_average"] is False
    assert payload["promotion"]["progress"] == 1.0


# --- certificate progress --------------------------------------------------


async def test_certificate_numbers_follow_the_per_course_portfolio(client, db_session):
    """A tutor-wide total is not a certificate.

    The profile here says 1234 minutes, but no course has a verified competency
    or a completed session behind it. A certificate is earned per course, so the
    certificate screen answers with an empty portfolio and the dashboard must
    not report hours the screen cannot see. The threshold still comes from
    settings on both, which is the half that must never drift.
    """
    body, _user, _profile = await _tutor(
        client,
        db_session,
        "tutor@mak.ac.ug",
        certified_minutes=1234,
    )

    hq = (await client.get("/v1/tutors/me", headers=_bearer(body))).json()
    certificate = (
        await client.get("/v1/incentives/certificate", headers=_bearer(body))
    ).json()

    assert certificate["courses"] == []
    assert hq["certified_minutes"] == 0
    assert hq["certificate_eligible"] is False
    assert hq["certificate_progress"] == 0.0
    assert hq["certificate_remaining_minutes"] == (
        get_settings().certificate_required_minutes
    )
    assert (
        hq["certificate_required_minutes"]
        == get_settings().certificate_required_minutes
    )


# --- availability ----------------------------------------------------------


async def test_a_tutor_can_pause_and_resume_requests(client, db_session):
    """The switch is written, not echoed, and the read reflects it."""
    body, _user, profile = await _tutor(
        client, db_session, "tutor@mak.ac.ug", accepting_requests=True
    )

    paused = await client.patch(
        "/v1/tutors/me",
        headers=_bearer(body),
        json={"accepting_requests": False},
    )

    assert paused.status_code == 200, paused.text
    assert paused.json()["accepting_requests"] is False

    stored = await db_session.scalar(
        select(TutorProfile).where(TutorProfile.user_id == profile.user_id)
    )
    assert stored is not None
    assert stored.accepting_requests is False

    read_back = await client.get("/v1/tutors/me", headers=_bearer(body))
    assert read_back.json()["accepting_requests"] is False

    resumed = await client.patch(
        "/v1/tutors/me",
        headers=_bearer(body),
        json={"accepting_requests": True},
    )
    assert resumed.status_code == 200, resumed.text
    assert resumed.json()["accepting_requests"] is True


async def test_pausing_is_idempotent(client, db_session):
    """A double tap must not fail, and must not need a read-modify-write."""
    body, _user, _profile = await _tutor(client, db_session, "tutor@mak.ac.ug")

    first = await client.patch(
        "/v1/tutors/me",
        headers=_bearer(body),
        json={"accepting_requests": False},
    )
    second = await client.patch(
        "/v1/tutors/me",
        headers=_bearer(body),
        json={"accepting_requests": False},
    )

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert second.json()["accepting_requests"] is False


async def test_a_student_cannot_pause_requests_they_do_not_have(client, db_session):
    """A write with no profile is a 404, unlike the read."""
    body, _user = await _account(client, db_session, "student@mak.ac.ug")

    response = await client.patch(
        "/v1/tutors/me",
        headers=_bearer(body),
        json={"accepting_requests": False},
    )

    assert response.status_code == 404, response.text


async def test_the_settings_body_rejects_unknown_fields(client, db_session):
    """A misspelled setting must not look like it was applied."""
    body, _user, _profile = await _tutor(client, db_session, "tutor@mak.ac.ug")

    response = await client.patch(
        "/v1/tutors/me",
        headers=_bearer(body),
        json={"accepting_request": False},
    )

    assert response.status_code == 422, response.text

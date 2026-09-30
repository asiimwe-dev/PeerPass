"""RFC 9457 problem documents."""

import pytest

from app.core.exceptions import (
    AuthenticationProblem,
    AuthorizationProblem,
    ConflictProblem,
    NotFoundProblem,
    ProblemException,
    ValidationProblem,
)


def test_problem_carries_the_required_members() -> None:
    """RFC 9457 requires type, title, status, and detail."""
    problem = ProblemException("Something is wrong.").to_problem("/v1/things")

    assert problem["status"] == 400
    assert problem["detail"] == "Something is wrong."
    assert problem["instance"] == "/v1/things"
    assert problem["type"].startswith("https://")
    assert problem["title"]


def test_problem_omits_optional_members_when_unset() -> None:
    problem = ProblemException("Something is wrong.").to_problem("/v1/things")

    assert "errors" not in problem
    assert "code" not in problem


def test_validation_problem_exposes_per_field_reasons() -> None:
    problem = ValidationProblem(
        errors={"email": "Enter a valid email address"},
    ).to_problem("/v1/auth/register")

    assert problem["status"] == 422
    assert problem["errors"] == {"email": "Enter a valid email address"}


@pytest.mark.parametrize(
    ("exception", "expected_status"),
    [
        (AuthenticationProblem(), 401),
        (AuthorizationProblem(), 403),
        (NotFoundProblem(), 404),
        (ConflictProblem(), 409),
        (ValidationProblem(), 422),
    ],
)
def test_each_problem_type_maps_to_its_status(
    exception: ProblemException, expected_status: int
) -> None:
    assert exception.status_code == expected_status


def test_problem_messages_do_not_disclose_the_callers_roles() -> None:
    """An error message must not describe why authorization failed.

    401 and 403 already tell the caller which case applied, and the two
    messages are deliberately distinct because the remedy differs: sign in
    again, or do not attempt this. What must not leak is the internal reason --
    a role name or a competency state would tell an attacker exactly which
    account to target.
    """
    messages = [AuthenticationProblem().detail, AuthorizationProblem().detail]

    for message in messages:
        assert message
        for role in ("student", "tutor", "verified_tutor"):
            assert role not in message.lower()

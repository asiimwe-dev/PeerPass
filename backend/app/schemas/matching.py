"""Matching schemas: what the platform is willing to propose.

The response says why a tutor was or was not proposed. A bare list of names is
not something a student can argue with, and a tutor who is passed over with no
reason has no way to learn what to fix -- which is the behaviour that decides
whether anyone keeps uploading evidence.
"""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import Field

from app.schemas.base import OrmSchema, RequestSchema
from app.schemas.tutor import TutorProfileSummary

MIN_WIDENING_FACTOR = 1
MAX_WIDENING_FACTOR = 5

#: How many candidates one request may return. Beyond this a student is not
#: choosing, they are scrolling, and the ranked list has stopped doing its job.
MAX_MATCH_CANDIDATES = 20


class MatchRequest(RequestSchema):
    """Ask for tutors for a course unit.

    `widen_to_subject` is the only search behaviour a client may request, and it
    is opt-in. Widening by default would quietly return tutors who cannot help
    with the course the student actually asked about, which is worse than
    returning none and saying so.
    """

    course_unit_id: uuid.UUID
    widen_to_subject: bool = Field(
        default=False,
        description=(
            "Fall back to the whole subject when the exact unit has no eligible "
            "tutor. Reported in the response as `widened`."
        ),
    )
    limit: int = Field(default=MAX_MATCH_CANDIDATES, ge=1, le=MAX_MATCH_CANDIDATES)


class MatchExclusion(OrmSchema):
    """A tutor who was considered and ruled out.

    `reason` is a stable code, not prose, so the client can branch on it. The
    codes are the matching rules, and they are also the answer to "why is my
    verified tutor not showing up".
    """

    tutor_id: uuid.UUID
    reason: str = Field(
        description=(
            "One of: below_threshold, unverified, suspended, same_university_only, "
            "already_booked, not_the_tutor."
        )
    )


class MatchCandidate(OrmSchema):
    """An eligible tutor, with the evidence behind the ranking."""

    tutor: TutorProfileSummary
    course_unit_id: uuid.UUID
    competency_grade_points: Decimal = Field(max_digits=6, decimal_places=2)
    meets_threshold: bool
    score: float = Field(
        description=(
            "Ranking score, higher is better. Relative only: the client shows "
            "order, not a number a student could compare across requests."
        )
    )


class MatchResponse(OrmSchema):
    """The outcome of one matching call.

    `no_eligible_tutors` is sent explicitly rather than left as an empty list, so
    the app can say why nothing appeared instead of showing a blank screen that
    reads as a loading failure.
    """

    request_id: uuid.UUID = Field(
        description="The help request these candidates answer.",
    )
    course_unit_id: uuid.UUID
    widened: bool = Field(
        default=False,
        description="True when the exact unit had no eligible tutor and the "
        "subject was searched instead.",
    )
    candidates: list[MatchCandidate] = Field(default_factory=list)
    exclusions: list[MatchExclusion] = Field(
        default_factory=list,
        description="Considered and ruled out. Sent to the student, who is the "
        "only one who can act on it.",
    )
    no_eligible_tutors: bool = False
    generated_at: datetime

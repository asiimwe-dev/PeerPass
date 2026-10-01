"""Certificate eligibility for the signed-in tutor.

One route, and it takes no subject. There is no path parameter, no query
parameter, and no body: the caller is the only account this answers about, which
is the whole authorisation rule. A route that took a `user_id` would be a route
whose only question is whether the caller checked the right box, and the answer
it gives is one a tutor has no standing to have.

Not on the tutor rail or the tutor detail response. Those are student-facing
discovery views, and `TutorProfileSummary` is the single type that policy lives
in -- so "how many minutes this tutor is from a certificate" would have to be
added to the type every student-facing view shares, to be answered for a tutor
other than the caller, on a screen where a student's question is whether this
person can help them. The minutes are the tutor's own business and are reachable
from one endpoint about their own account.
"""

from fastapi import APIRouter

from app.api.deps import CurrentUser, DatabaseSession
from app.schemas.tutor import CertificateEligibilityResponse
from app.services import incentive_service

router = APIRouter(prefix="/incentives", tags=["incentives"])


@router.get(
    "/certificate",
    response_model=CertificateEligibilityResponse,
    summary="My certificate eligibility",
)
async def my_certificate_eligibility(
    caller: CurrentUser,
    db: DatabaseSession,
) -> CertificateEligibilityResponse:
    """The caller's own hours, the configured threshold, and the verdict.

    Answers for a user with no tutor profile too: `has_tutor_profile` says so,
    and the arithmetic is all zero. That is a real answer about a real state --
    they are not a tutor yet -- rather than a 404, which would put a signed-in
    student's screen into an error state over something they did not do wrong.

    The threshold travels on the wire. A client that carried its own copy of the
    number would keep telling tutors the old one after the threshold was lowered
    for a pilot, and the two answers would disagree with each other in the field
    and nowhere in review.
    """
    return await incentive_service.get_certificate_eligibility(db, caller.user)

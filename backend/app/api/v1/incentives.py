"""Per-course certificates for the signed-in tutor.

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
from app.schemas.tutor import CertificatePortfolioResponse
from app.services import incentive_service

router = APIRouter(prefix="/incentives", tags=["incentives"])


@router.get(
    "/certificate",
    response_model=CertificatePortfolioResponse,
    summary="My certificates",
)
async def my_certificates(
    caller: CurrentUser,
    db: DatabaseSession,
) -> CertificatePortfolioResponse:
    """One entry per course this tutor can earn a certificate for.

    A certificate is awarded per course, so the answer is a portfolio rather
    than a single total: 15 hours split across three courses is not 15 hours in
    any of them. Each entry carries its own verdict and its own configured
    thresholds, and the list is ordered earned first, then closest to earned.

    Answers for a user with no tutor profile too: `has_tutor_profile` says so,
    and `courses` is empty. That is a real answer about a real state -- they are
    not a tutor yet -- rather than a 404, which would put a signed-in student's
    screen into an error state over something they did not do wrong.
    """
    return await incentive_service.get_certificate_portfolio(db, caller.user)

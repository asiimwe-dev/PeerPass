"""Tutor hours and certificate business logic.

The certificate is an incentive, and it is deliberately a different kind of rule
from the standing in `rating_service`. Promotion answers "can this tutor be
offered work", from ratings and session count; this answers "has this tutor put
in enough hours", from one stored counter and one configured threshold. Neither
consults the other, and standing is not read here: a suspended tutor still has
the hours they taught, and quietly withholding them would be a product decision
about what a suspension means for an incentive nobody has written down.

The threshold is configuration rather than a constant because it is a thing a
product owner tunes between pilots, not a rule engineering should have to defend
in review. It is read per call rather than captured at import, so lowering it
takes effect on the next request instead of at the next deploy.
"""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.tutor_profile import TutorProfile
from app.models.user import User
from app.schemas.tutor import CertificateEligibilityResponse


async def get_certificate_eligibility(
    db: AsyncSession, user: User
) -> CertificateEligibilityResponse:
    """How close the signed-in user is to a certificate.

    The only subject is the caller. There is no user parameter beyond the
    authenticated one, so there is no question of whose standing is being read:
    an answer about someone else's hours is not a thing this function can
    produce, and `GET /v1/incentives/certificate` takes nothing to change that.

    A user with no `TutorProfile` is answered rather than refused or created
    one. The row belongs to a user holding the tutor role and is created when
    the role is granted, so a missing one means "not a tutor yet" -- a real
    state, not an error, and a student opening the screen should be told their
    hours rather than shown a failure or handed a standing they were never
    assessed for. Creating the row here would be the `rating_service` bug again:
    a read that hands every signed-in student a `probationary` standing and a
    certificate total of zero merely by opening a screen.
    """
    profile = await db.scalar(
        select(TutorProfile).where(TutorProfile.user_id == user.id)
    )
    required = get_settings().certificate_required_minutes
    certified = profile.certified_minutes if profile is not None else 0

    return CertificateEligibilityResponse(
        has_tutor_profile=profile is not None,
        # `>=`, and the comparison is on the stored integer rather than on
        # anything derived from it: exactly the configured threshold is
        # eligible, one minute less is not, and no display rounding sits between
        # the counter and the verdict.
        eligible=certified >= required,
        certified_minutes=certified,
        required_minutes=required,
        remaining_minutes=max(required - certified, 0),
        progress=_progress(certified, required),
        generated_at=datetime.now(UTC),
    )


def _progress(certified: int, required: int) -> float:
    """The fraction of the threshold reached, clamped to the 0.0-1.0 the wire declares.

    A display value, and sent rather than left to the client so that "how far
    along" has one answer: a client that divided the two numbers itself would be
    free to disagree about the clamp, and a tutor two hours past the threshold
    would see a bar at 105%.

    The division cannot be by zero. `certificate_required_minutes` is `gt=0` in
    configuration, so a zero threshold fails startup rather than reaching here.
    `Decimal` so the quotient is taken in the base the threshold is stated in and
    the float is only ever rendered, never compared against anything.
    """
    if certified >= required:
        return 1.0
    return float(Decimal(certified) / Decimal(required))

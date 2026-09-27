"""Tutor profile schemas: standing, and the counters it is derived from.

The counters are sent as the stored total and count, not as a pre-computed
average. The division needs the scale's precision to be reproduced exactly, and
sending a rounded mean would leave the client unable to show the same number the
promotion rule was applied with.

A `Decimal` is serialised as a JSON *string* -- `"4.10"`, not `4.1`. That is
Pydantic's default and it is deliberate: a JSON number becomes a double on the
Dart side, and a double cannot represent every `numeric(6,2)` value, so a string
means no value is silently rounded on its way to the client. The client parses it
with `double.parse` for display, which is all it does with it -- every threshold
comparison happens server-side, against the `Decimal`, before serialisation.
"""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import Field

from app.models.enums import TutorStanding
from app.schemas.base import OrmSchema

MAX_SUSPENSION_REASON_LENGTH = 500


class TutorProfileResponse(OrmSchema):
    """A tutor's public standing."""

    id: uuid.UUID = Field(validation_alias="public_id")
    user_id: uuid.UUID = Field(validation_alias="user.public_id")
    standing: TutorStanding
    completed_sessions: int = Field(ge=0)
    certified_minutes: int = Field(
        ge=0,
        description="Minutes that counted towards a certificate.",
    )
    rating_total: Decimal = Field(max_digits=10, decimal_places=2, ge=0)
    rating_count: int = Field(ge=0)
    average_rating: Decimal | None = Field(
        default=None,
        max_digits=10,
        decimal_places=2,
        description=(
            "Mean score, or null with no ratings yet. Null rather than zero: a "
            "tutor with no ratings is not badly rated, and zero would fail a "
            "minimum-rating test for the wrong reason."
        ),
    )
    suspended_reason: str | None = Field(
        default=None,
        max_length=MAX_SUSPENSION_REASON_LENGTH,
        description=(
            "Why the tutor was suspended. Sent to the tutor themself and to an "
            "administrator; never to a student, who has standing to see that a "
            "tutor is suspended but no standing to read the reason."
        ),
    )


class TutorProfileSummary(OrmSchema):
    """The tutor fields a student sees when browsing matches.

    A trimmed `TutorProfileResponse` rather than the full one, because the
    suspension reason and the raw rating total are the tutor's own business. A
    `suspended` standing is included deliberately: hiding it would let a student
    accept a session with someone the platform has already suspended.
    """

    user_id: uuid.UUID
    full_name: str
    standing: TutorStanding
    average_rating: Decimal | None = Field(
        default=None, max_digits=10, decimal_places=2
    )
    completed_sessions: int = Field(ge=0)


class CertificateEligibilityResponse(OrmSchema):
    """Whether a tutor has earned a certificate, and how far off they are.

    Reports the shortfall as well as the verdict. A tutor who is told only "not
    yet" cannot tell whether they need one more session or forty, and the
    incentive that motivates teaching disappears.
    """

    eligible: bool
    certified_minutes: int = Field(ge=0)
    required_minutes: int = Field(gt=0)
    remaining_minutes: int = Field(ge=0)
    generated_at: datetime

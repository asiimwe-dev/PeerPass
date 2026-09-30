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
from app.schemas.base import MeanRating, OrmSchema

MAX_SUSPENSION_REASON_LENGTH = 500

#: How many entries the "top tutors" rail returns when the client says nothing.
#: Ten is a rail, not a list: enough to scroll past, few enough that a student
#: reads the ordering rather than the page numbers.
DEFAULT_RAIL_TUTORS = 10

#: The most entries one rail may return. A bound rather than a statement about
#: how many tutors exist: the rail is a discovery surface over the caller's own
#: university, and a client asking for thousands of rows off a metered
#: connection is either a bug or an attempt at a full table scan. Matching's own
#: `MAX_MATCH_CANDIDATES` is the same kind of bound.
MAX_RAIL_TUTORS = 20

#: How many endorsed course units one rail entry names.
#:
#: The count travels in full -- a rail row has to be able to say "endorsed 14
#: times" without a second request -- but the *list* is capped. A tutor who has
#: taught thirty units is not summarised by any five of them, and a client that
#: has to lay out thirty chips in a horizontal rail is not going to lay out any
#: of them. Truncation is why the entries carry the total: the number shown is
#: the whole truth and the list is a sample of it.
RAIL_ENDORSED_UNITS = 5


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
    average_rating: MeanRating | None = Field(
        default=None,
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
    average_rating: MeanRating | None = Field(default=None)
    completed_sessions: int = Field(ge=0)


class TutorRailEntry(OrmSchema):
    """One tutor as the browse rail shows them.

    Flat rather than a wrapped `TutorProfileSummary` because a rail row is a list
    cell: the client renders it without opening anything, and every field on it
    has to be readable at a glance. It repeats the summary's fields rather than
    embedding it for the same reason -- a row the client cannot open cannot
    afford a nesting level it would have to unwrap.

    Built by keyword from a query, never validated off an ORM object. There is
    no model carrying `user_id` as a *public* id, so the arrangement the rest of
    this package relies on -- a `validation_alias` pointing at a
    `*_public_id` property -- has nothing to point at here, and an unaliased
    `user_id` handed a `TutorProfile` would quietly become its primary key.
    Every value is filled in by the service from `User.public_id` and
    `TutorProfile`, which is the only place a leaked key could come from.
    """

    user_id: uuid.UUID
    full_name: str = Field(
        max_length=160,
        description=(
            "Display name, falling back to the account's email address. An "
            "account with no name is a real state, not an error."
        ),
    )
    standing: TutorStanding
    average_rating: MeanRating | None = Field(
        default=None,
        description="Mean score, or null with no ratings yet.",
    )
    completed_sessions: int = Field(ge=0)
    endorsed_course_unit_ids: list[uuid.UUID] = Field(
        default_factory=list,
        max_length=RAIL_ENDORSED_UNITS,
        description=(
            "Public ids of the units this tutor has been endorsed for, most "
            f"endorsed first and capped at {RAIL_ENDORSED_UNITS}. Empty when "
            "there is no endorsement, which is absence of evidence rather than "
            "a claim that they are weak in every unit."
        ),
    )
    endorsement_count: int = Field(
        ge=0,
        description=(
            "Total endorsements across every unit, which can exceed the number "
            "of units listed above."
        ),
    )


class TutorDetailResponse(OrmSchema):
    """One tutor's profile as the detail screen shows it.

    `profile` is the whole summary rather than a copy of its fields, so the
    detail screen is bounded by the same policy as every other student-facing
    view: whatever `TutorProfileSummary` refuses to carry -- the suspension
    reason, the raw rating total -- cannot be added here without changing the
    type every other student-facing view shares. Flattening the five fields
    would put that policy in five places instead of one, and one of them would
    be wrong within a month.
    """

    profile: TutorProfileSummary
    endorsed_course_unit_ids: list[uuid.UUID] = Field(
        default_factory=list,
        max_length=RAIL_ENDORSED_UNITS,
        description=(
            "The same capped sample the rail carries, for the same reason: a "
            "tutor endorsed in thirty units is not summarised by any five of "
            "them, so the count beside this list is the number to trust."
        ),
    )
    endorsement_count: int = Field(ge=0)


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

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
from app.schemas.base import MeanRating, OrmSchema, RequestSchema

MAX_SUSPENSION_REASON_LENGTH = 500

#: How long a tutor's bio may be.
#:
#: The same bound as the model's column. A bio is read inside a card, so the
#: limit is a layout decision as much as a storage one.
MAX_BIO_LENGTH = 280

#: How long an avatar URL may be.
MAX_AVATAR_URL_LENGTH = 500

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
    avatar_url: str | None = Field(
        default=None,
        max_length=MAX_AVATAR_URL_LENGTH,
        description=(
            "A photo when the tutor has one. Null is the normal beta state: the "
            "client draws a generated avatar from the name, so a tutor is never "
            "represented by an empty frame."
        ),
    )
    bio: str | None = Field(
        default=None,
        max_length=MAX_BIO_LENGTH,
        description=(
            "A few sentences in the tutor's own voice. Null when they have not "
            "written one, which is a normal state and not a reason to hide "
            "their other evidence."
        ),
    )
    year_of_study: int | None = Field(
        default=None,
        ge=1,
        le=6,
        description=(
            "The tutor's year, when they have declared it. Useful context for "
            "a student choosing between two people who look equally qualified."
        ),
    )
    accepting_requests: bool = Field(
        default=True,
        description=(
            "Whether the tutor is currently taking new requests. A paused "
            "tutor does not appear in matching; the rail still shows them with "
            "this flag set so a student who has met them can see why."
        ),
    )


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
    avatar_url: str | None = Field(
        default=None,
        max_length=MAX_AVATAR_URL_LENGTH,
        description="A photo when the tutor has one; null draws a generated avatar.",
    )
    bio: str | None = Field(
        default=None,
        max_length=MAX_BIO_LENGTH,
        description=(
            "A few sentences in the tutor's own voice, or null when they have "
            "not written one. The card falls back to their evidence, so a "
            "missing bio is not a missing card."
        ),
    )
    year_of_study: int | None = Field(default=None, ge=1, le=6)
    accepting_requests: bool = Field(
        default=True,
        description=(
            "False when the tutor has paused new requests. The rail shows them "
            "with the flag set; matching leaves them out."
        ),
    )
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
    """Whether the signed-in tutor has earned a certificate, and how far off they are.

    Reports the shortfall as well as the verdict. A tutor who is told only "not
    yet" cannot tell whether they need one more session or forty, and the
    incentive that motivates teaching disappears.

    The certificate has three conditions -- minutes, completed sessions, and a
    maintained average over enough rated sessions -- and each travels with its
    own `*_met` flag so the screen can name the outstanding one. The three
    verdicts are `>=` comparisons applied server-side against the stored
    integers and the exact `Decimal` mean. `certified_minutes` is sent as the
    stored integer, not rounded to a display scale: rounding would put a number
    on the wire that the verdict was not computed from. `MeanRating` exists
    because a mean of integer scores need not fit in two decimal places; it is
    serialised as a decimal string so no value is silently rounded on its way
    to the client.
    """

    has_tutor_profile: bool = Field(
        description=(
            "Whether the caller has a tutor profile at all. Sent rather than "
            "left for the client to infer, because a student with no profile and "
            "a new tutor with zero minutes are both `0 of 900` arithmetically "
            "and are not the same thing to the person reading it: the first is "
            "not on this path, the second has not started. Mirrors the `None` "
            "rather than zero that `average_rating` uses for the same reason."
        )
    )
    eligible: bool
    certified_minutes: int = Field(ge=0)
    required_minutes: int = Field(
        gt=0,
        description=(
            "The configured threshold in minutes, sent so the client renders "
            "the operator's number rather than one of its own. A client that "
            "hardcoded the default would keep showing 15 hours after the "
            "threshold was tuned for a pilot."
        ),
    )
    remaining_minutes: int = Field(ge=0)
    completed_sessions: int = Field(
        ge=0,
        description="Sessions the tutor has completed, across every course unit.",
    )
    required_sessions: int = Field(
        gt=0,
        description=(
            "The configured session threshold. Sent for the same reason as "
            "`required_minutes`: the client must render the operator's number, "
            "not a shipped default."
        ),
    )
    remaining_sessions: int = Field(ge=0)
    rating_count: int = Field(
        ge=0,
        description=(
            "How many ratings back `average_rating`. The rating condition needs "
            "both a count and an average; a tutor with one five-star session has "
            "not maintained anything yet."
        ),
    )
    average_rating: MeanRating | None = Field(
        default=None,
        description="The stored mean, or null when the tutor has no ratings.",
    )
    required_average_rating: MeanRating = Field(
        description="The configured minimum mean, as the operator set it."
    )
    minutes_met: bool = Field(
        description="Whether the teaching-hours condition is met on its own."
    )
    sessions_met: bool = Field(
        description="Whether the completed-session condition is met on its own."
    )
    rating_met: bool = Field(
        description=(
            "Whether the rating condition is met on its own: enough ratings and "
            "a high enough average."
        )
    )
    progress: float = Field(
        ge=0.0,
        le=1.0,
        description=(
            "How far along the tutor is: the smallest of the three requirement "
            "fractions, so the bar cannot read complete while any condition is "
            "outstanding. Clamped at 1.0."
        ),
    )
    generated_at: datetime


class CourseCertificateResponse(OrmSchema):
    """One course's progress towards its own certificate.

    A certificate is earned per course, not per tutor: the hours, sessions, and
    ratings that count are the ones recorded against this course unit. The three
    thresholds are repeated on each entry rather than sent once in an envelope,
    so a course card is self-contained and the client never has to join two
    objects to draw one bar. They are the same configured numbers on every entry;
    repeating a constant is cheaper than a shape that can disagree with itself.
    """

    course_unit_id: uuid.UUID = Field(
        description="Public id of the course this certificate is for."
    )
    course_unit_code: str
    course_unit_name: str
    eligible: bool
    certified_minutes: int = Field(ge=0)
    required_minutes: int = Field(gt=0)
    remaining_minutes: int = Field(ge=0)
    completed_sessions: int = Field(ge=0)
    required_sessions: int = Field(gt=0)
    remaining_sessions: int = Field(ge=0)
    rating_count: int = Field(ge=0)
    average_rating: MeanRating | None = Field(
        default=None,
        description="This course's stored mean, or null with no ratings.",
    )
    required_average_rating: MeanRating = Field(
        description="The configured minimum mean, as the operator set it."
    )
    minutes_met: bool
    sessions_met: bool
    rating_met: bool
    progress: float = Field(
        ge=0.0,
        le=1.0,
        description=(
            "The smallest of the three fractions for this course, so the bar "
            "cannot read complete while any condition is outstanding."
        ),
    )


class CertificatePortfolioResponse(OrmSchema):
    """Every course the caller can earn a certificate for, closest first.

    A tutor who teaches three courses has three separate certificates to earn,
    and a combined total would let one very long course carry the others over
    the bar. The list is ordered by the server -- earned first, then closest to
    earned, then course code -- so the dashboard summary can show the first entry
    without applying an ordering rule of its own.
    """

    has_tutor_profile: bool = Field(
        description=(
            "Whether the caller has a tutor profile at all. A student and a new "
            "tutor both have an empty list; only the second is on the path."
        )
    )
    courses: list[CourseCertificateResponse]
    generated_at: datetime


class TutorPromotionProgress(OrmSchema):
    """How far a tutor is from Verified, with both halves of the rule.

    Promotion has two conditions, not one: a tutor must be rated often enough
    *and* average at least the promotion bar. A single "3 of 3" ring would tell
    a tutor they are finished while their average is still below 4.10, so the
    two halves travel separately and the client can say which one is outstanding.

    `rated_sessions` is deliberately the rating count rather than
    `completed_sessions`. The promotion rule counts ratings, and a completed
    session its student has not rated yet -- a normal state, because the rating
    is a second action -- must not advance the ring. Showing the completed count
    here would be a number the rule does not use.

    `progress` is the session-count fraction, clamped at 1.0. It is a display
    value only: it says how much of the evidence exists, not whether the tutor
    is eligible, which is why `meets_average` and `verified` travel beside it.
    """

    verified: bool = Field(
        description=(
            "Whether the stored standing is `verified`. Read from the standing "
            "rather than recomputed from the thresholds, because a verified "
            "tutor keeps the badge until the explicit demotion bar is crossed."
        )
    )
    rated_sessions: int = Field(
        ge=0,
        description=(
            "How many ratings the tutor has. The promotion rule counts these, "
            "not completed sessions; an unrated session has not closed the loop."
        ),
    )
    sessions_required: int = Field(
        gt=0,
        description=(
            "The configured number of rated sessions required for promotion. "
            "Sent so the client renders the rule the server applied rather than "
            "a hardcoded copy of it."
        ),
    )
    sessions_remaining: int = Field(
        ge=0,
        description="Rated sessions still needed. Zero once the count is met.",
    )
    minimum_average: Decimal = Field(
        max_digits=10,
        decimal_places=2,
        description=(
            "The average a tutor must reach. A string on the wire, like every "
            "other decimal, so no value is rounded on its way to the client."
        ),
    )
    meets_average: bool = Field(
        description=(
            "Whether the current average is at or above `minimum_average`. "
            "False with no ratings yet: absence of evidence is not a pass."
        )
    )
    progress: float = Field(
        ge=0.0,
        le=1.0,
        description=(
            "Rated sessions as a fraction of `sessions_required`, clamped. "
            "Display only -- `meets_average` and `verified` are the verdicts."
        ),
    )


class TutorHqResponse(OrmSchema):
    """The signed-in tutor's own HQ: standing, counters, and availability.

    Only ever about the caller. There is no user parameter on the route and no
    id in the body, which is the whole authorisation rule: a tutor's hours,
    average, and availability are their own business, and this is the one place
    the client reads them together.

    `has_tutor_profile` is sent rather than inferred from the caller's role.
    Holding the tutor role and having a profile can disagree for a moment -- the
    role is granted before the first competency is verified -- and a student
    opening the screen is a real state with its own next step, not a broken
    tutor. When it is false, every counter is zero and `standing` and
    `accepting_requests` are null: the same `None`-rather-than-zero distinction
    `average_rating` uses, because "not on this path" is not "has not started".
    """

    has_tutor_profile: bool
    standing: TutorStanding | None = Field(
        default=None,
        description="The stored standing, or null when the caller has no profile.",
    )
    completed_sessions: int = Field(ge=0)
    average_rating: MeanRating | None = Field(
        default=None,
        description="Mean score, or null with no ratings yet.",
    )
    rating_count: int = Field(ge=0)
    certified_minutes: int = Field(
        ge=0,
        description="Minutes that counted towards a certificate.",
    )
    certificate_required_minutes: int = Field(
        gt=0,
        description="The configured certificate threshold, as an operator set it.",
    )
    certificate_remaining_minutes: int = Field(ge=0)
    certificate_eligible: bool
    certificate_progress: float = Field(ge=0.0, le=1.0)
    accepting_requests: bool | None = Field(
        default=None,
        description=(
            "Whether the tutor is taking new requests, or null when there is no "
            "profile to take them from."
        ),
    )
    promotion: TutorPromotionProgress


class UpdateTutorSettingsRequest(RequestSchema):
    """A change to the caller's own tutor settings.

    One field for now. The availability switch is the only tutor setting the
    client can change in the beta; bio and photo editing are not exposed, and
    adding them here without the screens that collect them would be a contract
    nothing exercises.
    """

    accepting_requests: bool = Field(
        description=(
            "False pauses new requests. Matching leaves a paused tutor out "
            "immediately, which is what makes the switch a promise rather than "
            "a label."
        )
    )

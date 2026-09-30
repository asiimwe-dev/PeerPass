"""Rating schemas.

The bounds are restated here as well as in the database. Duplicating them is
deliberate: a client gets a field-level message naming `score` instead of a 409
from a constraint, and a client that is not talking to this API can still see
what a valid score is.
"""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Self

from pydantic import Field, model_validator

from app.models.rating import MAX_RATING, MIN_RATING
from app.schemas.base import MeanRating, OrmSchema, RequestSchema, Trimmed

MAX_FEEDBACK_LENGTH = 2000

#: How many course units one rating may endorse.
#:
#: A session is booked for exactly one course unit, so the largest list the
#: service will ever *accept* today is one. The cap is not a statement about what
#: is legal -- it is a bound on what a client may make the server look up. A
#: payload naming thousands of units is either a client bug or an attempt to turn
#: a single form submission into thousands of existence checks, and both should
#: be refused at the edge rather than after the work has been done.
#:
#: Five leaves room for the shape this will plausibly grow into -- a session that
#: legitimately covers a unit and its co-requisites -- without making the field
#: unbounded in the meantime. Raise it when a session can genuinely be about
#: more than a handful of units, not before.
MAX_ENDORSEMENTS_PER_RATING = 5


class RatingCreate(RequestSchema):
    """Scoring a session you attended.

    There is no `session_id` field, and that is on purpose. The route takes the
    session from its path, so a client cannot rate a session it was not part of
    by sending someone else's id, and the rater and ratee are filled in by the
    service from the session rather than trusted from the body.

    `endorsed_course_unit_ids` is the *other* half of the same submission and is
    separate from `score` for the reason set out in `app.models.endorsement`: the
    score is a judgement of the tutor, the endorsement is a claim about coverage.

    It is optional, and empty by default, because endorsement is optional. Not
    every session deserves one -- a tutor who turned up late has earned a score,
    and a student who did not want to say more should not be pushed into saying
    something. A client that cannot express "no endorsement" is a client that
    will make people endorse to get past a form.

    Only the session's own course unit can be endorsed, and that is enforced in
    the service rather than here: it is a comparison against existing state, not
    a property of the request body.
    """

    score: int = Field(
        ge=MIN_RATING,
        le=MAX_RATING,
        description=f"Whole score from {MIN_RATING} to {MAX_RATING}.",
    )
    feedback_text: Trimmed | None = Field(default=None, max_length=MAX_FEEDBACK_LENGTH)
    endorsed_course_unit_ids: list[uuid.UUID] = Field(
        default_factory=list,
        max_length=MAX_ENDORSEMENTS_PER_RATING,
        description=(
            "Public ids of the course units the tutor actually covered. Empty "
            "means no endorsement, which is a legitimate submission."
        ),
    )

    @model_validator(mode="after")
    def endorsed_units_are_unique(self) -> Self:
        """The same unit may not appear twice in one submission.

        The database refuses a duplicate row outright, so without this the
        client would get an unhandled integrity error for something it can be
        told plainly. A duplicate is also never meaningful: the rater is making
        one claim about one unit, and listing it twice is not a stronger claim.
        """
        seen: set[uuid.UUID] = set()
        for course_unit_id in self.endorsed_course_unit_ids:
            if course_unit_id in seen:
                raise ValueError("endorsed_course_unit_ids must not contain duplicates")
            seen.add(course_unit_id)
        return self


class RatingResponse(OrmSchema):
    """A rating, with its rater and ratee resolved to public ids.

    `rater_id` and `ratee_id` are sent to the recipient, not to an audience: a
    student sees who rated a session of theirs, and a tutor sees who rated their
    teaching. Neither is shown to a third party.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    session_id: uuid.UUID = Field(validation_alias="session_public_id")
    rater_id: uuid.UUID = Field(validation_alias="rater_public_id")
    ratee_id: uuid.UUID = Field(validation_alias="ratee_public_id")
    score: int
    feedback_text: str | None = None
    created_at: datetime


class UnitEndorsementCount(OrmSchema):
    """How many sessions one tutor was endorsed for in one course unit.

    A raw count and nothing else. This is deliberately not a score: a per-unit
    average would need a decay model, a minimum-sample rule and an agreed way to
    show "not enough endorsements yet" to a student, and inventing those here
    would bake a matching policy into a transport type. Counts are the input that
    policy will later read.

    No `validation_alias`, unlike the schemas built from an ORM object. There is
    no ORM object here: the service groups in the database and hands over a row
    that already carries the *public* course unit id, so there is nothing for
    `from_attributes` to pick up and no attribute for an alias to point at. The
    rule the alias normally enforces -- a response body carries public ids and
    never primary keys -- is enforced by the query joining `course_units` for
    its public id rather than reading the endorsement's key column.
    """

    course_unit_id: uuid.UUID
    endorsement_count: int = Field(ge=0)


class TutorRatingSummary(OrmSchema):
    """A tutor's rating history, aggregated for their profile.

    The same total and count the promotion rule is computed from, so the number
    the tutor sees is the number the platform acted on.

    `per_unit` is separate from that total on purpose. A global average says a
    tutor is good; it does not say *at what*, and "4.8 overall" is compatible
    with a tutor who has never been endorsed for the unit a student is asking
    about. Units with no endorsement are absent rather than present with a zero,
    because an absent entry is not a claim that the tutor is weak there and a zero
    would be exactly that.
    """

    average_rating: MeanRating | None = Field(
        default=None,
        description="Null with no ratings yet; zero would read as badly rated.",
    )
    rating_total: Decimal = Field(max_digits=10, decimal_places=2, ge=0)
    rating_count: int = Field(ge=0)
    recent: list[RatingResponse] = Field(
        default_factory=list,
        description="Most recent first. Bounded by the page parameters.",
    )
    per_unit: list[UnitEndorsementCount] = Field(
        default_factory=list,
        description="Endorsement counts per course unit, most endorsed first.",
    )

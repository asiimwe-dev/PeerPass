"""Rating schemas.

The bounds are restated here as well as in the database. Duplicating them is
deliberate: a client gets a field-level message naming `score` instead of a 409
from a constraint, and a client that is not talking to this API can still see
what a valid score is.
"""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import Field

from app.models.rating import MAX_RATING, MIN_RATING
from app.schemas.base import OrmSchema, RequestSchema, Trimmed

MAX_FEEDBACK_LENGTH = 2000


class RatingCreate(RequestSchema):
    """Scoring a session you attended.

    There is no `session_id` field, and that is on purpose. The route takes the
    session from its path, so a client cannot rate a session it was not part of
    by sending someone else's id, and the rater and ratee are filled in by the
    service from the session rather than trusted from the body.
    """

    score: int = Field(
        ge=MIN_RATING,
        le=MAX_RATING,
        description=f"Whole score from {MIN_RATING} to {MAX_RATING}.",
    )
    feedback_text: Trimmed | None = Field(default=None, max_length=MAX_FEEDBACK_LENGTH)


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


class TutorRatingSummary(OrmSchema):
    """A tutor's rating history, aggregated for their profile.

    The same total and count the promotion rule is computed from, so the number
    the tutor sees is the number the platform acted on.
    """

    average_rating: Decimal | None = Field(
        default=None,
        max_digits=10,
        decimal_places=2,
        description="Null with no ratings yet; zero would read as badly rated.",
    )
    rating_total: Decimal = Field(max_digits=10, decimal_places=2, ge=0)
    rating_count: int = Field(ge=0)
    recent: list[RatingResponse] = Field(
        default_factory=list,
        description="Most recent first. Bounded by the page parameters.",
    )

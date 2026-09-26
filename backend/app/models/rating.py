"""Post-session ratings.

The rule that a completed session requires a rating is *not* enforced here, and
it cannot be: it spans `sessions` and `ratings`, and a CHECK constraint may only
reference columns of its own row. PostgreSQL could express it as a deferred
constraint trigger, at the cost of making the schema harder to read and to
migrate for a rule that has exactly one legitimate enforcement point.

It is therefore a service-layer rule -- see `app.services.sessions` -- and this
module's job is to make enforcing it possible rather than to pretend to: the
score is bounded, a rater cannot rate the same session twice, and
`Session.is_rated` is the check that rule is written against.
"""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Integer,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import TimestampMixin, public_id_column

if TYPE_CHECKING:
    from app.models.session import Session
    from app.models.user import User

#: The bounds of the rating scale. Stated once so the schema check, the schemas,
#: and the tests cannot disagree about what a valid score is.
MIN_RATING = 1
MAX_RATING = 5


class Rating(Base, TimestampMixin):
    """One person's assessment of one session."""

    __tablename__ = "ratings"
    __table_args__ = (
        # One rating per person per session. A retried submit updates the
        # existing row instead of adding a second score that would be averaged
        # in twice.
        UniqueConstraint("session_id", "rater_id", name="rating_per_rater"),
        CheckConstraint(
            f"score >= {MIN_RATING} AND score <= {MAX_RATING}",
            name="score_within_scale",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )

    rater_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    #: The other party. Stored rather than derived from the session so a rating
    #: survives the session row being archived, and so a query for a tutor's
    #: feedback does not have to join through sessions.
    ratee_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    score: Mapped[int] = mapped_column(Integer, nullable=False)

    #: Optional free text from the rater. A tutor suspended on a low average is
    #: entitled to know which session drove it, which is why this is kept rather
    #: than discarded with the rest of the rating.
    feedback_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    session: Mapped["Session"] = relationship(back_populates="ratings")
    rater: Mapped["User"] = relationship(foreign_keys=[rater_id])
    ratee: Mapped["User"] = relationship(foreign_keys=[ratee_id])

    def __repr__(self) -> str:
        return f"<Rating {self.score} by {self.rater_id}>"

"""Unit-scoped endorsements: what a tutor actually covered in a session.

An endorsement is deliberately *not* a rating and is not derived from one. They
answer different questions and the difference is the whole point:

- `Rating.score` answers "how was this tutor" -- a judgement about manner and
  quality that stays meaningful whichever unit the session was about.
- An endorsement answers "what did they cover" -- a claim about subject matter,
  scoped to one course unit, which is what a student comparing two tutors who
  both score 4.8 actually needs.

Putting the second on the first would mean either a `course_unit_id` column on
`ratings` that is meaningless for the many sessions nobody endorses, or a score
that is quietly carrying a claim about coverage as well as about quality. Both
would make the rating table stop being the record of one person's assessment and
start being the record of two, and the standing rules that read it would then be
reading a number that no longer means what its name says.

An endorsement is therefore its own row, hung off the same session, written in
the same transaction as the rating that prompted it and replaceable by it. It is
*optional*: a student who was shown up to by a tutor they did not find useful is
entitled to say so with a score and no endorsement, and a client that cannot
express that is a client that will make people lie.

Nothing here computes a per-unit score, and that is not an omission. A weighted
"4.8 in Calculus, 3.1 in Statistics" figure is a product decision with a decay
model, a minimum-sample rule and a display attached to it; it belongs in a change
that makes it deliberately, not as a byproduct of storing the counts.
"""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import TimestampMixin, public_id_column

if TYPE_CHECKING:
    from app.models.course_unit import CourseUnit
    from app.models.session import Session
    from app.models.user import User


class UnitEndorsement(Base, TimestampMixin):
    """One rater vouching that one ratee covered one course unit, in one session.

    Scoped to the session rather than to the pair of people on purpose. A tutor
    who taught the same student three sessions of MAT 221 has been endorsed in
    MAT 221; what matters to the student choosing between tutors is the subject
    and the number of sessions behind it, not which Tuesday the claim started on.
    Scoping to the session also keeps the unique key below honest: there is
    exactly one thing a rater can say about a given session and unit, so a
    retried submit has to replace it rather than add to it.
    """

    __tablename__ = "unit_endorsements"
    __table_args__ = (
        # A rater endorses a unit once per session. Retrying the submission, or
        # correcting it, must land on the same row rather than adding a second
        # claim that the aggregate below would count twice.
        UniqueConstraint(
            "session_id",
            "rater_id",
            "course_unit_id",
            name="endorsement_per_rater_unit",
        ),
        # Mirrors `session_parties_differ`. A self-endorsement is a claim about
        # someone vouching for themselves, which is either a bug or an attempt
        # to inflate the per-unit count the matching engine will later read, and
        # neither should need a service to be trusted in order to refuse.
        CheckConstraint("rater_id <> ratee_id", name="endorsement_parties_differ"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    #: The session whose coverage is being vouched for. Cascades, because the
    #: claim is about something that happened: if the session row goes, the
    #: endorsement it produced has nothing left to refer to, and keeping it
    #: would leave a count that no session backs.
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )

    #: Who is vouching. Always a party to the session; the service fills both
    #: from the session rather than trusting the body, exactly as it does for a
    #: rating.
    rater_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    #: The tutor being endorsed. Stored rather than derived from the session for
    #: the same reason `Rating` stores its own `ratee_id`: the per-unit aggregate
    #: reads it directly, so it does not have to join through sessions to answer
    #: "which units has this tutor been endorsed for".
    ratee_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    #: The unit that was covered. `RESTRICT` because a unit is reference data a
    #: student's transcript points at; an endorsement that blocked its removal
    #: because it happened to be mentioned once would be reference data that
    #: could never be retired.
    course_unit_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("course_units.id", ondelete="RESTRICT"), nullable=False, index=True
    )

    #: Read-side only. Nothing in the application walks from a session or a user
    #: to its endorsements, so there is no `back_populates` here: declaring a
    #: reverse collection nobody reads would be a write path with no caller.
    #:
    #: `passive_deletes` on the cascading foreign keys, for the reason given on
    #: `Session.ratings`: the database removes these rows itself, and loading
    #: them first would be both slower and a chance to lose a row the database
    #: would have removed anyway. The `course_unit` relationship does not set it
    #: -- there the foreign key is `RESTRICT`, and the deletion is supposed to
    #: fail.
    session: Mapped[Session] = relationship(passive_deletes=True)
    rater: Mapped[User] = relationship(foreign_keys=[rater_id], passive_deletes=True)
    ratee: Mapped[User] = relationship(foreign_keys=[ratee_id], passive_deletes=True)
    course_unit: Mapped[CourseUnit] = relationship()

    @property
    def session_public_id(self) -> uuid.UUID:
        return self.session.public_id

    @property
    def rater_public_id(self) -> uuid.UUID:
        return self.rater.public_id

    @property
    def ratee_public_id(self) -> uuid.UUID:
        return self.ratee.public_id

    @property
    def course_unit_public_id(self) -> uuid.UUID:
        return self.course_unit.public_id

    def __repr__(self) -> str:
        return f"<UnitEndorsement unit={self.course_unit_id} by {self.rater_id}>"

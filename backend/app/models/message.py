"""Messages the two parties of a session exchange with each other.

A message is not its own conversation. It belongs to a session, and the session
is what decides who may read it: the two people who agreed to meet already had
to be named on the same booking before either could write. That is the
difference between this and a general inbox -- there is no way to open a thread
with someone the app has not already matched you to, so the first message a
tutor receives is always from a student whose request they accepted.

The table holds all three phases of a session's life (before, during, and
after) because the product has no reason to close it. The venue is agreed before
the session, "I'm outside" is sent during it, and a follow-up question after it
is the same conversation with the same person. What a cancelled session gets is
the one exception: writing there is refused by the service, because there was
never a meeting to arrange.

`read_at` is a timestamp on the message rather than a per-reader row, which is
sound only because a session has exactly two parties: each row has one sender
and therefore one recipient. It is what the unread count is counted from, and
setting it is what opening the thread does.
"""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.core.security import new_uuid7
from app.models.base import TimestampMixin, public_id_column

if TYPE_CHECKING:
    from app.models.session import Session
    from app.models.user import User

#: One message. Long enough for a meeting place, a list of what to bring, and a
#: short paragraph of explanation; short enough that the table cannot be used as
#: free storage. Bounded in the database as well as in the schema, because the
#: two backends validate a request body differently and only one of them is
#: between a raw client and this table.
MAX_BODY_LENGTH = 2000


class SessionMessage(Base, TimestampMixin):
    """One message from one party of one session."""

    __tablename__ = "session_messages"
    __table_args__ = (
        CheckConstraint(
            f"length(body) > 0 AND length(body) <= {MAX_BODY_LENGTH}",
            name="body_length",
        ),
        # The thread read is "this session, oldest first", and the client polls it
        # with `after=<last id>`. One index serves both the first page and every
        # poll that follows.
        Index(
            "ix_session_messages_session_created",
            "session_id",
            "created_at",
        ),
        # The unread count per session, and the query behind "has the recipient
        # already got an unread message from this person". Partial would be
        # better on PostgreSQL, but SQLite cannot express one and the index is
        # small enough that the difference does not matter at this size.
        Index(
            "ix_session_messages_session_unread",
            "session_id",
            "read_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=new_uuid7)
    public_id: Mapped[uuid.UUID] = public_id_column()

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )

    sender_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    body: Mapped[str] = mapped_column(Text, nullable=False)

    #: Null means the recipient has not opened the thread since this arrived.
    #:
    #: Set by the recipient, never by the sender: a sender that could mark their
    #: own message read would clear the badge on the other person's phone.
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    session: Mapped[Session] = relationship()
    sender: Mapped[User] = relationship()

    def __repr__(self) -> str:
        return f"<SessionMessage {self.public_id}>"

    #: Public ids for the response schema.
    #:
    #: A schema field called `session_id` would otherwise be handed the internal
    #: foreign key by `from_attributes`, which looks right in a test and leaks a
    #: primary key in production. The service eager-loads both relationships, so
    #: reading them here never triggers a lazy load.
    @property
    def session_public_id(self) -> uuid.UUID:
        return self.session.public_id

    @property
    def sender_public_id(self) -> uuid.UUID:
        return self.sender.public_id

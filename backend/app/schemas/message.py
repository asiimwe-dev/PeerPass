"""Message transport types.

One message is one row the two parties of a session exchange. The response
carries both public ids the client needs -- which session, and which party wrote
it -- and nothing about the reader: the reader is whoever holds the access
token, and a thread can only ever be read by the two people on the session.

The body is trimmed at the edge and bounded by both the schema and the table.
An empty body is refused rather than stored, because a message with nothing in
it still marks the thread unread on the other person's phone.
"""

import uuid
from datetime import datetime

from pydantic import Field

from app.models.message import MAX_BODY_LENGTH
from app.schemas.base import OrmSchema, RequestSchema, Trimmed


class MessageCreate(RequestSchema):
    """What one party sends."""

    body: Trimmed = Field(
        min_length=1,
        max_length=MAX_BODY_LENGTH,
        description="The message itself, with surrounding whitespace removed.",
    )


class MessageResponse(OrmSchema):
    """One message, as either party reads it."""

    id: uuid.UUID = Field(validation_alias="public_id")
    session_id: uuid.UUID = Field(validation_alias="session_public_id")
    sender_id: uuid.UUID = Field(validation_alias="sender_public_id")
    body: str
    read_at: datetime | None = None
    created_at: datetime


class MessagesReadResponse(OrmSchema):
    """How many messages the caller's own read actually cleared.

    The count is reported rather than returned as a bare 204 so a client caught
    between two polls can tell "everything was already read" from "nothing was
    addressed to me", which are the two states that produce the same empty
    thread.
    """

    marked: int = Field(ge=0)

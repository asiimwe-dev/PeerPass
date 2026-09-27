"""Envelopes shared by more than one endpoint.

Pagination lives here rather than in each feature because the Flutter client
parses one shape for every list, and a list endpoint that invents its own
envelope would need a special case in the client forever.
"""

import math
from typing import TypeVar

from pydantic import Field, computed_field

from app.schemas.base import OrmSchema, RequestSchema

T = TypeVar("T")

#: Caps a single response so a client cannot ask for the whole table and turn a
#: metered connection into a full scan. Matching suggestions are the widest list
#: the pilot needs, and 100 is comfortably above that.
MAX_PAGE_SIZE = 100
DEFAULT_PAGE_SIZE = 20


class PageParams(RequestSchema):
    """`limit` and `offset` as query parameters.

    Offset paging rather than cursor paging because the pilot's lists are
    short-lived state -- a user's own sessions and help requests, which change
    while they are being read. Keyset paging would need a stable tiebreaker to
    be correct, and there is no natural one worth the complexity yet. If a list
    ever grows enough for deep offsets to matter, that is the moment to change,
    and the response envelope is where it will show.
    """

    limit: int = Field(
        default=DEFAULT_PAGE_SIZE,
        ge=1,
        le=MAX_PAGE_SIZE,
        description="Rows per page.",
    )
    offset: int = Field(
        default=0,
        ge=0,
        description="Rows to skip.",
    )


class Page[T](OrmSchema):
    """A page of results and enough state for the client to paginate.

    `total` is the count of matching rows, not of the page. A client that
    receives `items` alone cannot tell whether there is a next page, and
    rendering "no results" when there are forty more is a support ticket.
    """

    items: list[T]
    total: int = Field(ge=0, description="Rows matching the query in total.")
    limit: int = Field(ge=1)
    offset: int = Field(ge=0)

    @computed_field  # type: ignore[prop-decorator]
    @property
    def has_more(self) -> bool:
        return self.offset + len(self.items) < self.total

    @computed_field  # type: ignore[prop-decorator]
    @property
    def page_count(self) -> int:
        return math.ceil(self.total / self.limit) if self.limit else 0


class MessageResponse(OrmSchema):
    """A body for endpoints whose only result is that something succeeded.

    Deliberately not an empty object. A client confirming a destructive action
    wants the identifier of what it acted on, and an empty `{}` gives it nothing
    to show.
    """

    message: str

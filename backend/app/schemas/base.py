"""Shared Pydantic bases.

One rule runs through every schema in this package: **a response body carries
public ids and never primary keys.** The client is untrusted and its ids end up
in URLs, logs, and analytics, so a leaked primary key is a leaked row count. The
mechanism is a `validation_alias`, not a convention anyone has to remember:

```python
id: UUID = Field(validation_alias="public_id")
```

`from_attributes` then reads the public id, and because no *serialization* alias
is set the field is still emitted as `id`, whichever way FastAPI is configured to
dump. Declaring the field any other way does not fail loudly. An unaliased
`course_unit_id` would simply receive the internal key from the ORM object, look
right in a test, and be wrong in production -- so the models expose
`course_unit_public_id` and the schemas alias to those instead.

Request schemas are the opposite: they may only carry public ids, and validation
here is the first line of defence against a client inventing an internal one.
"""

from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, StringConstraints

#: A string whose surrounding whitespace is noise and is removed. Applied per
#: field rather than through `ConfigDict`, because the config would reach
#: passwords too.
#:
#: `Field(str_strip_whitespace=True)` is the obvious spelling and is wrong: it is
#: deprecated in Pydantic v2, and a deprecated extra keyword is not an error -- it
#: is quietly dropped, leaving the field untrimmed and the trim it appeared to ask
#: for never happening.
Trimmed = Annotated[str, StringConstraints(strip_whitespace=True)]


def _round_to_cents(value: object) -> object:
    """Round an already-numeric mean to the two places the wire declares.

    Only a `Decimal` is touched. Anything else is passed through so Pydantic
    keeps reporting a bad value the way it always has, rather than this
    function deciding that a string or a float was "close enough".
    """
    if not isinstance(value, Decimal):
        return value
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


#: A mean of integer scores, as it leaves the service.
#:
#: Every schema carrying an `average_rating` declares `decimal_places=2`, and a
#: mean need not fit in two places: eight ratings totalling 33 average 4.125.
#: Pydantic v2 *validates* rather than rounds, so the exact mean raised a
#: validation error and the endpoint answered 500 -- a tutor whose ratings did
#: not divide evenly could not read their own standing, on the rail, on the
#: detail screen, or through `GET /v1/ratings/me`.
#:
#: Spelled `MeanRating | None` at the field rather than `Optional[MeanRating]`
#: inside the alias: Pydantic applies a known constraint to *every* member of an
#: `Optional[...]` it is handed, so the null that means "unrated" -- the case the
#: `None` exists for -- was rejected by the very constraint carrying it.
#:
#: Rounded here, at the edge, and nowhere else. `TutorProfile.average_rating`
#: stays exact because the promotion rule is an equality test on it: rounding
#: there would promote a tutor averaging 3.999 and demote one averaging 4.004,
#: which is a product decision no schema should be making.
MeanRating = Annotated[
    Decimal,
    BeforeValidator(_round_to_cents),
    Field(max_digits=10, decimal_places=2),
]

__all__ = ["MeanRating", "OrmSchema", "RequestSchema", "Trimmed"]


class RequestSchema(BaseModel):
    """A body the client sent.

    `extra="forbid"` rather than the Pydantic default of ignoring unknown keys.
    Silently dropping a misspelled field means the client believes it set
    something it did not -- a `score` sent as `rating` would create a rating with
    no score, or a tutor status change that never happened. Rejecting is louder
    and cheaper to debug.

    `str_strip_whitespace` is deliberately *not* set here, and each field that
    wants trimming asks for it. Applying it at the base would strip a password's
    leading and trailing spaces, so `"correct horse battery "` would be stored
    and compared as `"correct horse battery"`. The user who typed a trailing space
    once at sign-up and not at sign-in is locked out, and a password whose spaces
    are meaningful has been quietly rewritten -- with no error anywhere to notice
    it by.
    """

    model_config = ConfigDict(extra="forbid")


class OrmSchema(BaseModel):
    """A body built from a model instance.

    `from_attributes` so a route can return a model directly. `frozen` because
    these are transport types: nothing should mutate a response after it is
    built, and freezing turns that from a subtle bug into an error.

    `populate_by_name` so a schema can also be built by keyword using the wire
    name. A `validation_alias` otherwise forces every construction site to spell
    it `public_id`, which is a wart with no benefit: the alias exists to make
    `model_validate` read the right attribute off an ORM object, and the alias
    still wins there. Hand construction has no model behind it, so there is no
    internal key available to pick up by mistake.
    """

    model_config = ConfigDict(from_attributes=True, frozen=True, populate_by_name=True)

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

from typing import Annotated

from pydantic import BaseModel, ConfigDict, StringConstraints

#: A string whose surrounding whitespace is noise and is removed. Applied per
#: field rather than through `ConfigDict`, because the config would reach
#: passwords too.
#:
#: `Field(str_strip_whitespace=True)` is the obvious spelling and is wrong: it is
#: deprecated in Pydantic v2, and a deprecated extra keyword is not an error -- it
#: is quietly dropped, leaving the field untrimmed and the trim it appeared to ask
#: for never happening.
Trimmed = Annotated[str, StringConstraints(strip_whitespace=True)]

__all__ = ["OrmSchema", "RequestSchema", "Trimmed"]


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

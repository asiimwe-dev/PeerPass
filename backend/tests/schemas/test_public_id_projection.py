"""Every response id resolves to a public id, proven against the real models.

These are the checks that stop an internal primary key reaching a client. A
`validation_alias` pointing at an attribute the model does not have is a silent
failure: the route works, the field raises `AttributeError` or quietly falls back
to a null, and the leak only shows up in a payload someone is reading.

A hand-maintained map of schema to model is deliberate. Inferring it from naming
would re-derive the same convention the test exists to verify.
"""

from __future__ import annotations

import uuid

import pytest
from pydantic import BaseModel, ValidationError

from app import schemas
from app.core.database import Base
from app.models import (
    Competency,
    CourseUnit,
    Grade,
    GradingScale,
    HelpRequest,
    Rating,
    Session,
    Subject,
    TutorProfile,
    University,
    User,
)
from app.schemas.base import OrmSchema
from app.schemas.session import SessionResponse

SCHEMA_MODELS: dict[str, type[Base]] = {
    "CompetencyResponse": Competency,
    "CourseUnitResponse": CourseUnit,
    "GradeResponse": Grade,
    "GradingScaleResponse": GradingScale,
    "HelpRequestResponse": HelpRequest,
    "RatingResponse": Rating,
    "SessionResponse": Session,
    "SubjectResponse": Subject,
    "TutorProfileResponse": TutorProfile,
    "UniversityResponse": University,
    "UserResponse": User,
}


def _resolve(model: type[Base], path: str) -> None:
    """Assert every hop of a dotted attribute path exists on the class.

    `TutorProfileResponse.user_id` reads `"user.public_id"`, so the first hop is
    a relationship and the second is a column. Checking only the leaf would pass
    on a renamed relationship.
    """
    current: object = model
    for hop in path.split("."):
        assert hasattr(current, hop), f"{model.__name__} has no attribute {path!r}"


def _orm_schemas() -> dict[str, type[BaseModel]]:
    return {
        name: getattr(schemas, name)
        for name in schemas.__all__
        if isinstance(getattr(schemas, name), type)
        and issubclass(getattr(schemas, name), OrmSchema)
    }


class TestPublicIdAliasesResolve:
    def test_every_alias_resolves_against_its_model(self) -> None:
        unresolved: dict[str, list[str]] = {}

        for name, model in SCHEMA_MODELS.items():
            missing = []
            for field in getattr(schemas, name).model_fields.values():
                alias = field.validation_alias
                if alias is None:
                    continue
                try:
                    _resolve(model, str(alias))
                except AssertionError:
                    missing.append(str(alias))
            if missing:
                unresolved[name] = missing

        assert unresolved == {}

    def test_no_response_field_falls_back_to_a_raw_key(self) -> None:
        """A `*_id` field with no alias reads the model's primary key.

        `from_attributes` resolves a missing alias by the field's own name, so
        `grading_scale_id` on a university would hand the client the internal
        UUID unless the alias overrides it. Silently, and only in production.
        """
        unaliased: dict[str, list[str]] = {}

        for name in SCHEMA_MODELS:
            leaks = [
                field
                for field, spec in getattr(schemas, name).model_fields.items()
                if field.endswith("_id") and spec.validation_alias is None
            ]
            if leaks:
                unaliased[name] = leaks

        assert unaliased == {}

    def test_every_mapped_model_has_a_public_id(self) -> None:
        """The invariant behind all of the above.

        Anything a response can reference must carry a public id, or the response
        would have to send the primary key to name it.
        """
        without = sorted(
            mapper.class_.__name__
            for mapper in Base.registry.mappers
            if not hasattr(mapper.class_, "public_id")
        )

        assert without == []

    def test_dotted_relationship_aliases_are_declared(self) -> None:
        """A relationship reached in a response must be loaded before it is read.

        An unloaded relationship in async SQLAlchemy raises instead of lazily
        loading, so a missing `selectinload` becomes a 500 rather than a wrong
        answer. Enumerating the set means adding a response field that reaches
        through a relationship has to be a deliberate edit here, alongside
        choosing the loader for it.
        """
        reached = {
            (model.__name__, str(alias).split(".")[0])
            for name, model in SCHEMA_MODELS.items()
            for alias in (
                str(f.validation_alias)
                for f in schemas.__dict__[name].model_fields.values()
                if f.validation_alias and "." in str(f.validation_alias)
            )
        }

        assert reached == {("TutorProfile", "user")}


class TestProjectedFieldsNeedAService:
    """Fields the model cannot hand over, so a service has to.

    `from_attributes` makes a response *look* like it can be returned straight
    from a query. It cannot, for these, and the reason differs in each case --
    which is why they are listed rather than assumed.
    """

    @pytest.mark.parametrize(
        ("schema_name", "field", "reason"),
        [
            (
                "UserResponse",
                "roles",
                "no ORM relationship; the role rows are an "
                "association table, so a query is needed",
            ),
            (
                "SessionResponse",
                "is_rated",
                "an async method taking a session, so "
                "reading the attribute yields a coroutine, not a bool",
            ),
            (
                "CompetencyResponse",
                "meets_threshold",
                "a method taking the "
                "threshold; the model has no field of that name to read",
            ),
            (
                "CompetencyResponse",
                "grade_points",
                "a denormalised total whose value is computed in the service",
            ),
        ],
    )
    def test_the_field_is_not_a_plain_model_attribute(
        self, schema_name: str, field: str, reason: str
    ) -> None:
        model = SCHEMA_MODELS[schema_name]
        raw = model.__dict__.get(field)

        # Absent, or present as something the model cannot simply read off. Both
        # mean the service has to supply the value. A plain attribute is the only
        # case that invalidates this expectation, and the message says so.
        assert raw is None or callable(raw) or isinstance(raw, property), (
            f"{model.__name__}.{field} is now a plain attribute the response can "
            f"read directly, so the service no longer has to supply it and this "
            f"expectation can be retired. Was: {reason}"
        )

    def test_validating_a_bare_model_does_not_silently_succeed(self) -> None:
        """The failure a route would hit, before a service layer exists.

        `model_validate` on an unpersisted instance with no relationships loaded
        has to raise rather than fill in a plausible-looking null. A null
        `is_rated` is indistinguishable from "nobody has rated it", which is the
        one value the completion rule cannot be allowed to guess.
        """
        session = Session(public_id=uuid.uuid4())

        with pytest.raises(ValidationError):
            SessionResponse.model_validate(session)

"""Transport types for the separate MUST admin surface."""

import uuid
from datetime import datetime

from pydantic import Field

from app.models.enums import (
    CompetencyStatus,
    TutorStanding,
    UserRole,
    VerificationSource,
)
from app.schemas.base import OrmSchema, RequestSchema
from app.schemas.common import Page


class AdminUserResponse(OrmSchema):
    """The minimum identity and status data staff need for pilot operations."""

    id: uuid.UUID
    email: str
    full_name: str | None
    roles: list[UserRole]
    university_id: uuid.UUID | None
    faculty_id: uuid.UUID | None
    year_of_study: int | None
    is_active: bool
    created_at: datetime


class AdminUserPage(Page[AdminUserResponse]):
    """A bounded page of users for the admin console."""


class AdminAuditEventResponse(OrmSchema):
    id: uuid.UUID = Field(validation_alias="public_id")
    actor_id: uuid.UUID
    action: str
    target_type: str
    target_public_id: uuid.UUID | None
    context: dict[str, object]
    created_at: datetime


class AdminAuditEventPage(Page[AdminAuditEventResponse]):
    """A bounded page of audit events."""


class AdminCompetencyResponse(OrmSchema):
    """The review fields staff need without embedding academic documents."""

    id: uuid.UUID
    user_id: uuid.UUID
    user_email: str
    user_name: str | None
    course_unit_id: uuid.UUID
    course_unit_code: str
    course_unit_name: str
    grade_points: str
    status: CompetencyStatus
    source: VerificationSource
    evidence_reference: str | None
    rejection_reason: str | None
    created_at: datetime


class AdminCompetencyPage(Page[AdminCompetencyResponse]):
    """A bounded page of tutor evidence awaiting or completing review."""


class AdminCompetencyReviewRequest(RequestSchema):
    """An audited admin decision on a tutor competency."""

    status: CompetencyStatus
    rejection_reason: str | None = None


class AdminTutorStandingResponse(OrmSchema):
    """Operational tutor standing and aggregate rating data."""

    user_id: uuid.UUID
    user_email: str
    user_name: str | None
    standing: TutorStanding
    completed_sessions: int
    rating_count: int
    average_rating: str | None


class AdminTutorStandingPage(Page[AdminTutorStandingResponse]):
    """A bounded page of tutor standing summaries."""

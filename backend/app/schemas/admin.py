"""Transport types for the separate MUST admin surface."""

import uuid
from datetime import datetime

from pydantic import Field

from app.models.enums import UserRole
from app.schemas.base import OrmSchema
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

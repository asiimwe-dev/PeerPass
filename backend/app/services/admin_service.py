"""Least-privilege read and audit operations for MUST staff."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.audit import AdminAuditEvent
from app.models.user import User, load_roles
from app.schemas.admin import (
    AdminAuditEventPage,
    AdminAuditEventResponse,
    AdminUserPage,
    AdminUserResponse,
)
from app.schemas.common import PageParams


async def list_users(
    db: AsyncSession, actor_id: uuid.UUID, params: PageParams
) -> AdminUserPage:
    """List users without passwords, tokens, consent timestamps, or evidence."""
    query = (
        select(User)
        .options(selectinload(User.university), selectinload(User.faculty))
        .order_by(User.created_at.desc(), User.id.desc())
    )
    total = await db.scalar(select(func.count()).select_from(query.subquery())) or 0
    users = list(
        (await db.scalars(query.offset(params.offset).limit(params.limit))).all()
    )
    items = [
        AdminUserResponse(
            id=user.public_id,
            email=user.email,
            full_name=user.full_name,
            roles=sorted(await load_roles(db, user.id), key=lambda role: role.value),
            university_id=user.university_public_id,
            faculty_id=user.faculty_public_id,
            year_of_study=user.year_of_study,
            is_active=user.is_active,
            created_at=user.created_at,
        )
        for user in users
    ]
    await record_audit(
        db,
        actor_id=actor_id,
        action="admin.users.list",
        target_type="user",
        context={"limit": params.limit, "offset": params.offset},
    )
    return AdminUserPage(
        items=items, total=total, limit=params.limit, offset=params.offset
    )


async def list_audit_events(
    db: AsyncSession, params: PageParams
) -> AdminAuditEventPage:
    query = select(AdminAuditEvent).order_by(
        AdminAuditEvent.created_at.desc(), AdminAuditEvent.id.desc()
    )
    total = await db.scalar(select(func.count()).select_from(query.subquery())) or 0
    events = list(
        (await db.scalars(query.offset(params.offset).limit(params.limit))).all()
    )
    return AdminAuditEventPage(
        items=[AdminAuditEventResponse.model_validate(event) for event in events],
        total=total,
        limit=params.limit,
        offset=params.offset,
    )


async def record_audit(
    db: AsyncSession,
    *,
    actor_id: uuid.UUID,
    action: str,
    target_type: str,
    target_public_id: uuid.UUID | None = None,
    context: dict[str, object] | None = None,
) -> None:
    """Record only allowlisted metadata and leave commit ownership to the route."""
    db.add(
        AdminAuditEvent(
            actor_id=actor_id,
            action=action,
            target_type=target_type,
            target_public_id=target_public_id,
            context=context or {},
        )
    )

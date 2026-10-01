"""Authenticated routes for the separate MUST admin application."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import AdminUser, DatabaseSession
from app.schemas.admin import AdminAuditEventPage, AdminUserPage
from app.schemas.common import PageParams
from app.services import admin_service

router = APIRouter(prefix="/admin", tags=["admin"])
AdminPageParams = Annotated[PageParams, Depends()]


@router.get("/users", response_model=AdminUserPage)
async def list_users(
    caller: AdminUser,
    db: DatabaseSession,
    params: AdminPageParams,
) -> AdminUserPage:
    """List pilot users with the minimum fields staff need to operate."""
    page = await admin_service.list_users(db, caller.user.id, params)
    await db.commit()
    return page


@router.get("/audit-events", response_model=AdminAuditEventPage)
async def list_audit_events(
    _caller: AdminUser,
    db: DatabaseSession,
    params: AdminPageParams,
) -> AdminAuditEventPage:
    """Read the append-only privileged-action log."""
    return await admin_service.list_audit_events(db, params)

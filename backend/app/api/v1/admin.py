"""Authenticated routes for the separate MUST admin application."""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import AdminUser, DatabaseSession
from app.schemas.admin import (
    AdminAuditEventPage,
    AdminCompetencyPage,
    AdminCompetencyPageParams,
    AdminCompetencyResponse,
    AdminCompetencyReviewRequest,
    AdminSessionReportPage,
    AdminSessionReportResponse,
    AdminSessionReportUpdate,
    AdminTutorStandingPage,
    AdminUserPage,
)
from app.schemas.common import PageParams
from app.services import admin_service

router = APIRouter(prefix="/admin", tags=["admin"])
AdminPageParams = Annotated[PageParams, Depends()]
CompetencyPageParams = Annotated[AdminCompetencyPageParams, Depends()]


async def _commit_read_audit(db: AsyncSession) -> None:
    """Commit the audit event an admin read recorded.

    A `GET` committing looks like a mistake until you know every privileged read
    writes an `AdminAuditEvent`: who looked at the pilot's users, competencies,
    standings, or reports is itself something the audit trail has to remember.
    `admin_service` deliberately leaves commit ownership to the route, so the
    commit lives here rather than in the service.

    Named rather than written as a bare `await db.commit()` so removing it is
    visibly removing the audit trail, not deleting what looks like a redundant
    write on a read path.
    """
    await db.commit()


@router.get("/users", response_model=AdminUserPage)
async def list_users(
    caller: AdminUser,
    db: DatabaseSession,
    params: AdminPageParams,
) -> AdminUserPage:
    """List pilot users with the minimum fields staff need to operate."""
    page = await admin_service.list_users(db, caller.user.id, params)
    await _commit_read_audit(db)
    return page


@router.get("/audit-events", response_model=AdminAuditEventPage)
async def list_audit_events(
    _caller: AdminUser,
    db: DatabaseSession,
    params: AdminPageParams,
) -> AdminAuditEventPage:
    """Read the append-only privileged-action log."""
    return await admin_service.list_audit_events(db, params)


@router.get("/competencies", response_model=AdminCompetencyPage)
async def list_competencies(
    caller: AdminUser,
    db: DatabaseSession,
    params: CompetencyPageParams,
) -> AdminCompetencyPage:
    """List the review queue, optionally narrowed to one status.

    Each row carries its grade label, the bar that grade has to clear, and
    whether it clears it, so an operator can see a refusal before making the
    decision that would be refused.
    """
    page = await admin_service.list_competencies(db, caller.user.id, params)
    await _commit_read_audit(db)
    return page


@router.patch(
    "/competencies/{competency_id}/review",
    response_model=AdminCompetencyResponse,
)
async def review_competency(
    competency_id: uuid.UUID,
    payload: AdminCompetencyReviewRequest,
    caller: AdminUser,
    db: DatabaseSession,
) -> AdminCompetencyResponse:
    response = await admin_service.review_competency(
        db, caller.user.id, competency_id, payload
    )
    await db.commit()
    return response


@router.get("/tutor-standings", response_model=AdminTutorStandingPage)
async def list_tutor_standings(
    caller: AdminUser,
    db: DatabaseSession,
    params: AdminPageParams,
) -> AdminTutorStandingPage:
    page = await admin_service.list_tutor_standings(db, caller.user.id, params)
    await _commit_read_audit(db)
    return page


@router.get("/session-reports", response_model=AdminSessionReportPage)
async def list_session_reports(
    caller: AdminUser,
    db: DatabaseSession,
    params: AdminPageParams,
) -> AdminSessionReportPage:
    page = await admin_service.list_session_reports(db, caller.user.id, params)
    await _commit_read_audit(db)
    return page


@router.patch(
    "/session-reports/{report_id}",
    response_model=AdminSessionReportResponse,
)
async def update_session_report(
    report_id: uuid.UUID,
    payload: AdminSessionReportUpdate,
    caller: AdminUser,
    db: DatabaseSession,
) -> AdminSessionReportResponse:
    response = await admin_service.update_session_report(
        db, caller.user.id, report_id, payload
    )
    await db.commit()
    return response

"""Admin authorization, privacy, pagination, and audit coverage."""

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AdminAuditEvent
from app.models.enums import UserRole
from app.models.user import User, set_roles
from tests.test_auth import headers_for, register


async def test_admin_routes_refuse_a_regular_user(client: AsyncClient) -> None:
    body = await register(client)

    response = await client.get("/v1/admin/users", headers=headers_for(body))

    assert response.status_code == 403
    assert response.json()["code"] == "not_permitted"


async def test_admin_user_list_is_paginated_safe_and_audited(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    body = await register(client)
    user = await db_session.scalar(
        select(User).where(User.email == "student@must.ac.ug")
    )
    assert user is not None
    await set_roles(db_session, user.id, {UserRole.STUDENT, UserRole.ADMIN})
    await db_session.commit()

    response = await client.get(
        "/v1/admin/users",
        params={"limit": 1, "offset": 0},
        headers=headers_for(body),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["total"] == 1
    assert payload["limit"] == 1
    assert payload["items"][0]["email"] == "student@must.ac.ug"
    assert "password_hash" not in payload["items"][0]
    assert "academic_data_consented_at" not in payload["items"][0]
    assert "evidence_reference" not in payload["items"][0]

    event = await db_session.scalar(
        select(AdminAuditEvent).where(AdminAuditEvent.action == "admin.users.list")
    )
    assert event is not None
    assert event.actor_id == user.id
    assert event.context == {"limit": 1, "offset": 0}

    audit_response = await client.get(
        "/v1/admin/audit-events", headers=headers_for(body)
    )
    assert audit_response.status_code == 200
    assert audit_response.json()["items"][0]["action"] == "admin.users.list"


async def test_admin_audit_route_requires_admin(client: AsyncClient) -> None:
    body = await register(client)

    response = await client.get("/v1/admin/audit-events", headers=headers_for(body))

    assert response.status_code == 403

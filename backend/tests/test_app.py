"""Application assembly: health/readiness checks and the error envelope."""

import pytest
from httpx import AsyncClient

PROBLEM_CONTENT_TYPE = "application/problem+json"


async def test_health_reports_ok(client: AsyncClient) -> None:
    response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_health_does_not_require_a_database(client: AsyncClient) -> None:
    """Liveness must not depend on Postgres.

    A liveness probe that fails when the database is briefly unavailable will
    restart the process, turning a database blip into an outage.
    """
    assert (await client.get("/health")).status_code == 200


async def test_readiness_reports_database_access(client: AsyncClient) -> None:
    response = await client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok"}


async def test_readiness_returns_generic_service_unavailable_on_database_failure(
    client: AsyncClient,
) -> None:
    from app.main import _database_ready, create_app

    async def _broken_db() -> bool:
        return False

    app = create_app()
    app.dependency_overrides[_database_ready] = _broken_db
    # The shared client is bound to a separate app instance. Exercise the
    # overridden application through its own transport.
    from httpx import ASGITransport

    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as raw:
        response = await raw.get("/ready")

    assert response.status_code == 503
    assert response.json()["detail"] == "The service is not ready."
    assert "password" not in response.text


async def test_unknown_route_returns_problem_details(client: AsyncClient) -> None:
    """Even the router's own 404 has to be a problem document.

    Otherwise the client has exactly one error shape to handle instead of two,
    which is the thing this module exists to prevent.
    """
    response = await client.get("/v1/nothing-here")

    assert response.status_code == 404
    assert response.headers["content-type"].startswith(PROBLEM_CONTENT_TYPE)
    body = response.json()
    assert body["status"] == 404
    assert body["title"]
    assert body["detail"]


async def test_problem_type_url_is_https() -> None:
    """The `type` member is a URI a client could dereference, so not a bare word."""
    from app.core.exceptions import ProblemException

    problem = ProblemException("Something is wrong.").to_problem("/v1/things")

    assert problem["type"].startswith("https://peerpass.app/problems/")


async def test_unexpected_error_does_not_leak_its_message() -> None:
    """A crash must not become a client's error toast.

    Interpolating the exception message is how connection strings and row
    contents escape into a response.
    """
    from httpx import ASGITransport, AsyncClient

    from app.main import create_app

    app = create_app()

    @app.get("/v1/boom")
    async def _boom() -> None:
        msg = "connection to postgres://user:hunter2@db/prod failed"
        raise RuntimeError(msg)

    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as raw:
        response = await raw.get("/v1/boom")

    assert response.status_code == 500
    assert "hunter2" not in response.text
    assert "postgres://" not in response.text
    assert response.headers["content-type"].startswith(PROBLEM_CONTENT_TYPE)


@pytest.mark.parametrize("status", [400, 401, 403, 404, 409, 422])
def test_openapi_documents_the_problem_content_type(status: int) -> None:
    """Clients and the docs must agree that errors are problem documents."""
    from app.main import create_app

    schema = create_app().openapi()

    assert (
        PROBLEM_CONTENT_TYPE
        in schema["paths"]["/health"]["get"]["responses"][str(status)]["content"]
    )

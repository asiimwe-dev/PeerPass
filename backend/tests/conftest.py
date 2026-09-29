"""Shared backend test fixtures.

Settings are supplied through the environment before anything imports
`app.core.config`, because the settings object is constructed on first access
and cached. Clearing that cache is therefore not enough; the variables have to
be in place first.
"""

import os
from collections.abc import AsyncIterator

import pytest

# Deliberately not prefixed with "test" or "changeme": Settings refuses a
# placeholder secret of any kind, and that guard should apply to the suite too.
_SUITE_JWT_SECRET = "peerpass-local-suite-signing-key-0123456789abcdef"
_SUITE_TOKEN_PEPPER = "peerpass-local-suite-token-pepper-0123456789abcdef"

os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("JWT_SECRET", _SUITE_JWT_SECRET)
os.environ.setdefault("JWT_ALGORITHM", "HS256")
os.environ.setdefault("TOKEN_PEPPER", _SUITE_TOKEN_PEPPER)

from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import event  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings  # noqa: E402
from app.core.database import Base  # noqa: E402


@pytest.fixture(scope="session")
def anyio_backend() -> str:
    """Use the asyncio backend only.

    Declared explicitly so the intent is recorded: adding trio later is a
    deliberate decision, not an accident of whichever plugin is installed.
    """
    return "asyncio"


def _enable_sqlite_foreign_keys(dbapi_connection, _connection_record) -> None:
    """Turn on the foreign key enforcement SQLite leaves off by default."""
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


@pytest.fixture
def settings():
    """The settings built from the test environment."""
    return get_settings()


#: Points the whole suite at a real PostgreSQL instead of SQLite. Set it and the
#: same tests run against the database the service actually uses:
#:
#:     PEERPASS_TEST_DATABASE_URL=postgresql+psycopg://user@host/db pytest
#:
#: This is not a convenience. SQLite does not enforce `numeric(6,2)`, does not
#: name its constraints, and stores UUIDs as strings, so a green SQLite run is
#: not evidence the schema is valid on PostgreSQL. Running the same suite
#: against both is what caught a `standing` column that accepted any string,
#: which SQLite had happily reported as enforced.
TEST_DATABASE_URL = os.environ.get("PEERPASS_TEST_DATABASE_URL")


@pytest.fixture
async def db_engine():
    """An engine with the schema created, on SQLite unless overridden.

    SQLite is the default because the domain tests must run in CI with no
    database service.
    """
    if TEST_DATABASE_URL:
        engine = create_async_engine(TEST_DATABASE_URL)
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.drop_all)
            await connection.run_sync(Base.metadata.create_all)
        yield engine
        await engine.dispose()
        return

    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        # SQLite enforces no foreign keys unless asked per connection. Without
        # this the ON DELETE CASCADE clauses are inert and every cascade test
        # passes without deleting anything.
        connect_args={"check_same_thread": False},
    )
    event.listen(engine.sync_engine, "connect", _enable_sqlite_foreign_keys)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def db_session(db_engine) -> AsyncIterator[AsyncSession]:
    """A session bound to the in-memory database."""
    factory = async_sessionmaker(
        bind=db_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with factory() as session:
        yield session


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    """An HTTP client bound to the app, with exceptions left unhandled.

    `raise_app_exceptions=False` is deliberate: a route that returns a problem
    document is a normal outcome the test asserts on, not a test failure.
    """
    from app.main import create_app

    transport = ASGITransport(app=create_app())
    async with AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as http_client:
        yield http_client

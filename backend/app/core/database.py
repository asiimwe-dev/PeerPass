"""SQLAlchemy engine, session factory, and declarative base.

Async throughout. The pilot's read paths are short and bursty, and an async
driver keeps a slow matching query from occupying a worker thread while a
student waits on a metered connection.

The engine is built on first use rather than at import. Building it eagerly
would make importing this module require a complete environment, which in turn
would break the Alembic CLI, the test suite, and any tool that only wants the
declarative base.
"""

from collections.abc import AsyncIterator
from functools import lru_cache

from sqlalchemy import MetaData
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

# Deterministic names for everything the schema creates without an explicit one.
# Two reasons this is not optional decoration:
#
# - Alembic detects a renamed constraint by name. A constraint whose name is
#   generated afresh on every migration looks like a drop plus an add, and a drop
#   of a constraint on a large table takes a lock and, for a unique index, drops
#   the guarantee for its duration.
# - A foreign key with no name is an anonymous constraint. Nothing can alter or
#   drop it later, and `alembic` has nothing to match on.
#
# It lives here rather than in `app.models` because it configures the metadata
# that `Base` owns, and core must not import from models.
NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_name)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    """Declarative base for every ORM model."""

    metadata = MetaData(naming_convention=NAMING_CONVENTION)


@lru_cache(maxsize=1)
def get_engine() -> AsyncEngine:
    """The process-wide engine, created on first use."""
    settings = get_settings()
    return create_async_engine(
        settings.database_url,
        echo=settings.database_echo,
        pool_pre_ping=True,
    )


@lru_cache(maxsize=1)
def get_session_factory() -> async_sessionmaker[AsyncSession]:
    """The session factory bound to [get_engine]."""
    return async_sessionmaker(
        bind=get_engine(),
        class_=AsyncSession,
        expire_on_commit=False,
        autoflush=False,
    )


async def get_db() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency yielding a request-scoped session.

    Rolls back on an unhandled exception. Committing is left to the service
    that performed the write, so a request that fails partway cannot leave half
    a change behind.
    """
    async with get_session_factory()() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise

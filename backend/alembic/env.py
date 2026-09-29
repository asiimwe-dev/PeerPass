"""Alembic environment.

Async, because the application is. The engine here is the sync driver over the
same URL rather than the application's async engine: Alembic's own DDL execution
is synchronous, and bridging that back into the event loop buys nothing except
two ways to fail. What the sync engine still shares with the service is the
`MetaData` and its naming convention, which is the part that has to match.
"""

from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool

from alembic import context
from app.core.config import get_settings
from app.core.database import Base

# The import is for its side effect. Without it, `Base.metadata` is empty and
# autogenerate cheerfully produces a migration that creates no tables.
import app.models  # noqa: F401  # isort: skip

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# The URL is not in `alembic.ini`, so that a migration cannot be pointed at a
# different database than the service. `x.replace` is URL escaping that the
# config parser would otherwise perform on the `%` characters that passwords
# routinely contain.
_url = get_settings().database_url.replace("%", "%%")
config.set_main_option("sqlalchemy.url", _url)


def run_migrations_offline() -> None:
    """Emit SQL to stdout without connecting.

    Used to review what a migration will do before running it, which on a table
    holding student records is worth being able to do.
    """
    context.configure(
        url=_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=True,
        # Makes the output readable SQL rather than a single unbroken line, and
        # adds the `--> statement:` markers.
        render_as_batch=False,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Connect and apply migrations."""

    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
            # Migrations that must rewrite a large table should opt into batch
            # mode explicitly in the revision itself. Making it the default
            # would silently rewrite operations that do not need it, which on
            # PostgreSQL is an expensive way to do nothing.
            render_as_batch=False,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

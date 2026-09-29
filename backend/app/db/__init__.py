"""Database seeding.

Separate from `app.core.database`, which owns the engine and the session
factory, and separate from the migrations in `alembic/`, which own the schema.
This package holds the scripts that fill a migrated database with the reference
data the product cannot boot without.
"""

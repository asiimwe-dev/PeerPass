"""Versioned API router assembly.

Every route is mounted under `/v1` here, and nowhere else. A route module
declares its own paths relative to the version prefix, so the prefix cannot drift
between modules and a future `/v2` is a single added line.
"""

from fastapi import APIRouter

from app.api.v1 import academics, auth, users

#: The version prefix is set here rather than at each `include_router` call, so
#: a new module cannot be added without it and the client has one place to look
#: for what the versioned surface is.
api_router = APIRouter(prefix="/v1")

api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(academics.router)

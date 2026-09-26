"""Versioned API router assembly.

Every route is mounted under `/v1` here, and nowhere else. A route module
declares its own paths relative to the version prefix, so the prefix cannot drift
between modules and a future `/v2` is a single added line.
"""

from fastapi import APIRouter

api_router = APIRouter()

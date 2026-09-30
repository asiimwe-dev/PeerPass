"""FastAPI application entry point.

Also the single place that turns an exception into a response. Routes raise a
[ProblemException]; they never build an error body, which is what guarantees
every error the client sees has the same shape.
"""

import logging

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.router import api_router
from app.core.config import get_settings
from app.core.exceptions import ProblemException

logger = logging.getLogger(__name__)

PROBLEM_CONTENT_TYPE = "application/problem+json"


def create_app() -> FastAPI:
    """Build the application.

    A factory rather than a module-level singleton so tests can construct an app
    with its own settings and its own database.
    """
    settings = get_settings()

    application = FastAPI(
        title="PeerPass API",
        version="0.1.0",
        default_response_class=JSONResponse,
        responses={
            400: {"content": {PROBLEM_CONTENT_TYPE: {}}},
            401: {"content": {PROBLEM_CONTENT_TYPE: {}}},
            403: {"content": {PROBLEM_CONTENT_TYPE: {}}},
            404: {"content": {PROBLEM_CONTENT_TYPE: {}}},
            409: {"content": {PROBLEM_CONTENT_TYPE: {}}},
            422: {"content": {PROBLEM_CONTENT_TYPE: {}}},
        },
    )

    if settings.cors_origins:
        from fastapi.middleware.cors import CORSMiddleware

        application.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    _register_exception_handlers(application)
    application.include_router(api_router)

    @application.get("/health", tags=["system"])
    def health_check() -> dict[str, str]:
        """Report service availability.

        Deliberately does not touch the database. A liveness probe that fails
        when Postgres is briefly unavailable will restart the process, which
        turns a database blip into an outage.
        """
        return {"status": "ok"}

    return application


def _register_exception_handlers(application: FastAPI) -> None:
    @application.exception_handler(ProblemException)
    async def _handle_problem(request: Request, exc: ProblemException) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=exc.to_problem(instance=str(request.url.path)),
            media_type=PROBLEM_CONTENT_TYPE,
        )

    @application.exception_handler(RequestValidationError)
    async def _handle_request_validation(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        """Convert FastAPI's own validation output into problem details.

        FastAPI's default shape is a list of objects keyed by `loc` and `msg`,
        which the client would have to know as a special case. Flattening it
        into `errors` keeps one shape for every rejection, whether it came from
        the framework or from a domain rule.
        """
        errors = {
            ".".join(str(part) for part in error["loc"][1:]) or "body": error["msg"]
            for error in exc.errors()
        }
        problem = ProblemException(
            "Some of the details you entered are not valid.",
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            title="Validation failed",
            code="validation_failed",
            errors=errors,
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            content=problem.to_problem(instance=str(request.url.path)),
            media_type=PROBLEM_CONTENT_TYPE,
        )

    @application.exception_handler(StarletteHTTPException)
    async def _handle_http_exception(
        request: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        """Render an HTTPException as problem details too.

        Without this, a 404 from the router's own no-match handling would be the
        only error in the API that is not a problem document.
        """
        problem = ProblemException(
            str(exc.detail),
            status_code=exc.status_code,
        )
        return JSONResponse(
            status_code=exc.status_code,
            content=problem.to_problem(instance=str(request.url.path)),
            media_type=PROBLEM_CONTENT_TYPE,
            headers=getattr(exc, "headers", None),
        )

    @application.exception_handler(Exception)
    async def _handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        """Log the cause, return nothing revealing.

        The detail is fixed rather than derived from the exception. Interpolating
        the message of an unexpected error is how connection strings and row
        contents end up in a client's error toast.
        """
        logger.exception("Unhandled error on %s", request.url.path, exc_info=exc)
        problem = ProblemException(
            "Something went wrong on our end.",
            status_code=500,
            title="Internal server error",
            code="internal_error",
        )
        return JSONResponse(
            status_code=500,
            content=problem.to_problem(instance=str(request.url.path)),
            media_type=PROBLEM_CONTENT_TYPE,
        )


app = create_app()

from fastapi.responses import RedirectResponse

@app.get("/", include_in_schema=False)
async def root_redirect():
    # Automatically bounces anyone visiting the bare URL to the API docs
    return RedirectResponse(url="/docs")
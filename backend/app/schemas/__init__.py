"""Pydantic transport types.

Request bodies and response bodies. No business rules live here: a schema
validates shape, and the services in `app.services` decide meaning. The one
exception is a cross-field rule that has no other natural home -- a rejection
without a reason, say -- and each of those says so where it is enforced.
"""

from app.schemas.academic import (
    CourseUnitResponse,
    GradeResponse,
    GradingScaleResponse,
    SubjectResponse,
    UniversityResponse,
)
from app.schemas.base import OrmSchema, RequestSchema
from app.schemas.common import (
    DEFAULT_PAGE_SIZE,
    MAX_PAGE_SIZE,
    MessageResponse,
    Page,
    PageParams,
)
from app.schemas.competency import (
    CompetencyCreate,
    CompetencyResponse,
    CompetencyReviewRequest,
)
from app.schemas.matching import (
    MatchCandidate,
    MatchExclusion,
    MatchRequest,
    MatchResponse,
)
from app.schemas.rating import (
    MAX_RATING,
    MIN_RATING,
    RatingCreate,
    RatingResponse,
    TutorRatingSummary,
)
from app.schemas.session import (
    HelpRequestCreate,
    HelpRequestResponse,
    SessionCreate,
    SessionResponse,
    SessionTransitionRequest,
)
from app.schemas.tutor import (
    CertificateEligibilityResponse,
    TutorProfileResponse,
    TutorProfileSummary,
)
from app.schemas.user import (
    AuthResponse,
    CurrentUserResponse,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)

__all__ = [
    "DEFAULT_PAGE_SIZE",
    "MAX_PAGE_SIZE",
    "MAX_RATING",
    "MIN_RATING",
    "AuthResponse",
    "CertificateEligibilityResponse",
    "CompetencyCreate",
    "CompetencyResponse",
    "CompetencyReviewRequest",
    "CourseUnitResponse",
    "CurrentUserResponse",
    "GradeResponse",
    "GradingScaleResponse",
    "HelpRequestCreate",
    "HelpRequestResponse",
    "LoginRequest",
    "MatchCandidate",
    "MatchExclusion",
    "MatchRequest",
    "MatchResponse",
    "MessageResponse",
    "OrmSchema",
    "Page",
    "PageParams",
    "RatingCreate",
    "RatingResponse",
    "RefreshRequest",
    "RegisterRequest",
    "RequestSchema",
    "SessionCreate",
    "SessionResponse",
    "SessionTransitionRequest",
    "SubjectResponse",
    "TokenResponse",
    "TutorProfileResponse",
    "TutorProfileSummary",
    "TutorRatingSummary",
    "UniversityResponse",
    "UserResponse",
]

"""Help request and session schemas.

A request is what a student asks for; a session is what happened. They are
separate resources on the wire as well as in the database, because a request can
sit unmatched or be withdrawn and must not appear as a session that never
occurred.

Status is never accepted from a client. A request or a session moves through
`status`, and the only field a client may set is the one its own action implies:
`cancelled_reason` and `cancelled_by` are recorded by the service from the
caller, because a client that can set them would let one user cancel another's
session and blame them.
"""

import uuid
from datetime import datetime
from typing import Self

from pydantic import Field, model_validator

from app.models.enums import HelpRequestStatus, SessionStatus
from app.schemas.base import OrmSchema, RequestSchema, Trimmed

MIN_TOPIC_LENGTH = 3
MAX_TOPIC_LENGTH = 200
MAX_DESCRIPTION_LENGTH = 2000
MAX_CANCELLATION_REASON_LENGTH = 500

MIN_DURATION_MINUTES = 1
MAX_DURATION_MINUTES = 480
MAX_VENUE_LENGTH = 160
ON_CAMPUS_CUSTOM_VENUE = "Other on-campus"
APPROVED_ON_CAMPUS_VENUES = frozenset(
    {"FCI Lab 1", "FCI Lab 2", "University Library", "Canteen", ON_CAMPUS_CUSTOM_VENUE}
)


class HelpRequestCreate(RequestSchema):
    """A student asking for help with a course unit.

    `topic` is required even though the course unit is known, because "MAT 221"
    is a course and "eigenvalues and diagonalisation" is the question, and a
    tutor deciding whether to accept needs the second one.
    """

    course_unit_id: uuid.UUID
    topic: Trimmed = Field(min_length=MIN_TOPIC_LENGTH, max_length=MAX_TOPIC_LENGTH)
    description: Trimmed | None = Field(
        default=None,
        max_length=MAX_DESCRIPTION_LENGTH,
        description="Optional detail, and not matched on.",
    )


class SelectTutorRequest(RequestSchema):
    """A student naming the tutor they have chosen from the proposals.

    One field, and it is deliberately not enough to be trusted. The service
    re-derives the eligible candidates for the request's own course unit and
    refuses a tutor who is not among them, because a request body is whatever
    the caller chose to send: invariant 1 is a server rule, and the fact that an
    id once appeared in a list the client holds is not evidence about the tutor's
    competency, grade, or standing now.

    Called `candidate_tutor_id` rather than the bare `tutor_id` the responses
    use, because a request body may not carry a plainly-named user id -- that
    spelling is read as a primary key that leaked onto the wire, and
    `test_no_request_schema_accepts_an_id_field` holds it out. What the field
    selects is the column the response then calls `matched_tutor_id`.
    """

    candidate_tutor_id: uuid.UUID


class HelpRequestResponse(OrmSchema):
    """A request as its owner and as a candidate tutor see it."""

    id: uuid.UUID = Field(validation_alias="public_id")
    tutee_id: uuid.UUID = Field(validation_alias="tutee_public_id")
    tutee_name: str | None = None
    course_unit_id: uuid.UUID = Field(validation_alias="course_unit_public_id")
    course_unit_code: str
    course_unit_name: str
    topic: str
    description: str | None = None
    status: HelpRequestStatus
    matched_tutor_id: uuid.UUID | None = Field(
        default=None, validation_alias="matched_tutor_public_id"
    )
    matched_tutor_name: str | None = None
    created_at: datetime


class SessionCreate(RequestSchema):
    """Booking a session against a matched request.

    `duration_minutes` is bounded at both ends. There is no floor of zero: a
    zero-length session would complete instantly and contribute to a
    certificate's hours, and there is no ceiling case either -- eight hours is
    past the longest a tutoring session plausibly runs, and an unbounded integer
    would let one row claim a year's worth of hours.
    """

    help_request_id: uuid.UUID | None = Field(
        default=None,
        description="The request being accepted, when there is one.",
    )
    course_unit_id: uuid.UUID
    topic: Trimmed = Field(min_length=MIN_TOPIC_LENGTH, max_length=MAX_TOPIC_LENGTH)
    duration_minutes: int = Field(ge=MIN_DURATION_MINUTES, le=MAX_DURATION_MINUTES)
    scheduled_start: datetime | None = None
    meeting_link: Trimmed | None = Field(
        default=None,
        max_length=500,
        description="Optional Google Meet / Zoom link the tutor shares.",
    )
    meeting_venue: Trimmed | None = Field(
        default=None,
        max_length=MAX_VENUE_LENGTH,
        description=(
            "Default on-campus venue, for example FCI Lab 1, University Library, "
            "or Canteen."
        ),
    )
    meeting_venue_detail: Trimmed | None = Field(
        default=None,
        max_length=MAX_VENUE_LENGTH,
        description=(
            "Room-level detail for campus locations. Required when "
            "meeting_venue is 'Other on-campus'."
        ),
    )

    @model_validator(mode="after")
    def start_is_in_the_future(self) -> Self:
        """A session cannot be scheduled in the past.

        Checked here rather than in the service because it is a property of the
        request, not of any existing state. A naive datetime is rejected by the
        comparison below, so a client in a timezone it did not mean cannot
        schedule a session that silently lands yesterday.
        """
        if self.scheduled_start is not None:
            if self.scheduled_start.tzinfo is None:
                raise ValueError("scheduled_start must include a timezone offset")
            if (
                self.scheduled_start.timestamp()
                <= datetime.now(self.scheduled_start.tzinfo).timestamp()
            ):
                raise ValueError("scheduled_start must be in the future")
        if self.meeting_venue == ON_CAMPUS_CUSTOM_VENUE and not (
            self.meeting_venue_detail and self.meeting_venue_detail.strip()
        ):
            raise ValueError(
                "meeting_venue_detail is required for an 'Other on-campus' venue"
            )
        if self.meeting_venue and self.meeting_venue not in APPROVED_ON_CAMPUS_VENUES:
            raise ValueError("meeting_venue must be an approved on-campus venue")
        if self.meeting_venue_detail and not self.meeting_venue:
            raise ValueError(
                "meeting_venue is required when meeting_venue_detail is provided"
            )
        return self


class SessionTransitionRequest(RequestSchema):
    """A caller moving a session to a new status.

    Only `status` and, for a cancellation, a reason. The service checks the move
    against `SESSION_TRANSITIONS` and records who did it; the client cannot
    assert that a session was completed, and cannot name a different actor.
    """

    status: SessionStatus
    cancellation_reason: Trimmed | None = Field(
        default=None, max_length=MAX_CANCELLATION_REASON_LENGTH
    )
    # No proof-of-attendance field. Starting a session is
    # `POST /v1/sessions/{id}/check-in` and finishing it is
    # `POST /v1/sessions/{id}/finish`, each called by both parties. Accepting a
    # field here and ignoring it would be worse than removing it, so a client
    # still sending one gets a 422 from `extra="forbid"`.

    @model_validator(mode="after")
    def reason_required_when_cancelling(self) -> Self:
        """A cancellation must say why.

        Both parties need it. The tutor deciding whether to keep teaching for
        this student, and the platform deciding whether a cancellation is a
        pattern. An unexplained cancellation is the single most common cause of a
        disputed rating, and it is the cheapest thing to record.
        """
        if self.status is SessionStatus.CANCELLED and not (
            self.cancellation_reason and self.cancellation_reason.strip()
        ):
            raise ValueError("cancellation_reason is required when cancelling")
        return self

    @model_validator(mode="after")
    def reason_rejected_when_not_cancelling(self) -> Self:
        """Only a cancellation carries a reason.

        Dropped silently otherwise so a client that reuses one form for every
        transition does not have to branch, and a stored reason cannot contradict
        a completed session.
        """
        if self.status is not SessionStatus.CANCELLED:
            object.__setattr__(self, "cancellation_reason", None)
        return self


class SessionResponse(OrmSchema):
    """A session as either party sees it.

    Carries both parties' public ids because both need to name the other, and
    because the two clients are the same app.

    The ids are joined by display names because a session card has to answer
    "who am I meeting, and for what", and an opaque public id answers neither.
    The names are additions beside the ids rather than replacements for them: the
    ids are what the client identifies records by, and a rename must not change
    the identity of a session the two parties already hold.
    """

    id: uuid.UUID = Field(validation_alias="public_id")
    help_request_id: uuid.UUID | None = Field(
        default=None, validation_alias="help_request_public_id"
    )
    tutee_id: uuid.UUID = Field(validation_alias="tutee_public_id")
    tutor_id: uuid.UUID = Field(validation_alias="tutor_public_id")
    course_unit_id: uuid.UUID = Field(validation_alias="course_unit_public_id")
    course_unit_code: str
    course_unit_name: str
    tutee_name: str | None = None
    tutor_name: str | None = None
    topic: str
    status: SessionStatus
    scheduled_start: datetime | None = None
    started_at: datetime | None = None
    ended_at: datetime | None = None
    tutor_checked_in_at: datetime | None = Field(
        default=None,
        description="When the tutor tapped check in. Null until they do.",
    )
    tutee_checked_in_at: datetime | None = Field(
        default=None,
        description="When the student tapped check in. Null until they do.",
    )
    tutor_finished_at: datetime | None = Field(
        default=None,
        description="When the tutor tapped finish. Null until they do.",
    )
    tutee_finished_at: datetime | None = Field(
        default=None,
        description="When the student tapped finish. Null until they do.",
    )
    duration_minutes: int = Field(ge=0)
    meeting_link: str | None = Field(
        default=None, description="Shared meeting link for the session."
    )
    meeting_venue: str | None = Field(
        default=None,
        description="On-campus venue label selected for the session.",
    )
    meeting_venue_detail: str | None = Field(
        default=None,
        description="Room-level on-campus venue detail.",
    )
    is_rated: bool = Field(
        description=(
            "Whether a rating exists yet. The client needs this to decide whether "
            "to prompt for one; a completed session is not rated yet is the state "
            "the prompt exists for."
        )
    )
    unread_message_count: int = Field(
        default=0,
        ge=0,
        description=(
            "Messages the other party wrote that this caller has not read. "
            "Counted per caller, so the same session reads zero for the sender."
        ),
    )
    created_at: datetime

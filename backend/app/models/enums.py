"""Enumerations shared by models, schemas, and services.

Kept in one module because a value has to mean the same thing in the database,
on the wire, and in a service. A duplicate definition in `schemas` is how a
column starts accepting a state the matching engine does not know how to handle.

Wire values are the bare lowercase name. They are part of the API contract, so
`StrEnum` is used deliberately: a rename is a breaking change and shows up as a
diff on these lines rather than as a silent behaviour change.
"""

from enum import StrEnum


class UserRole(StrEnum):
    """A role a person holds.

    A user holds several, which is why this is a join table rather than a column
    on `users`. A tutor is also a student, and the pilot needs both halves of
    that person to work.
    """

    STUDENT = "student"
    TUTOR = "tutor"
    ADMIN = "admin"


class VerificationSource(StrEnum):
    """Where the evidence for a competency came from.

    `MANUAL` exists for the documented override case: a faculty member or
    registry confirming a result that arrived by no electronic route. It is
    recorded explicitly rather than being indistinguishable from a transcript,
    because an override is exactly the thing an auditor asks about.
    """

    TRANSCRIPT = "transcript"
    PORTFOLIO = "portfolio"
    MANUAL = "manual"


class ReportCategory(StrEnum):
    SAFETY = "safety"
    HARASSMENT = "harassment"
    FRAUD = "fraud"
    VENUE = "venue"
    OTHER = "other"


class ReportStatus(StrEnum):
    OPEN = "open"
    REVIEWING = "reviewing"
    RESOLVED = "resolved"


class CompetencyStatus(StrEnum):
    """Verification state of one grade in one course unit.

    `PENDING` is the state a submission waits in. An unverified competency does
    not make a tutor eligible, so a pending record is stored rather than
    discarded: it is what the tutor sees as "awaiting review".
    """

    PENDING = "pending"
    VERIFIED = "verified"
    REJECTED = "rejected"


class TutorStanding(StrEnum):
    """A tutor's standing, derived from completed sessions and ratings.

    Not the same as [UserRole]: holding the tutor role is a fact about the
    account, while standing is a judgement about performance that changes.

    `PROBATIONARY` is the state every new tutor starts in.
    `VERIFIED` is reached by meeting both the session-count and average-rating
    thresholds.
    `REDUCED` means still eligible, but ranked below verified tutors.
    `SUSPENDED` removes them from matching for the affected units.
    """

    PROBATIONARY = "probationary"
    VERIFIED = "verified"
    REDUCED = "reduced"
    SUSPENDED = "suspended"


class HelpRequestStatus(StrEnum):
    """Lifecycle of a student's request for help.

    Separate from [SessionStatus] because a request outlives any single session:
    a request can be withdrawn or expire having never been matched, and a
    request that was matched can still be open if the session is cancelled.

    The three states the student chose their tutor created are what make this a
    *choice* rather than a queue. `PENDING_CONFIRMATION` is the request waiting
    on a named tutor to say yes, and `DECLINED` is that tutor saying no. Both
    are needed rather than one: without `PENDING_CONFIRMATION` a selected tutor
    is indistinguishable from an unselected one, and without `DECLINED` a
    declined request is indistinguishable from one nobody ever answered.
    """

    OPEN = "open"
    #: A tutor has been chosen and has been asked to confirm. The student is
    #: waiting; the tutor has not yet declined to.
    PENDING_CONFIRMATION = "pending_confirmation"
    #: The chosen tutor turned the request down. Kept as a terminal state
    #: rather than a flag so the reason a request died stays readable, and so
    #: the student can post a new one instead of reopening a dead thread.
    DECLINED = "declined"
    MATCHED = "matched"
    WITHDRAWN = "withdrawn"
    EXPIRED = "expired"


class SessionStatus(StrEnum):
    """Lifecycle of a tutoring session.

    Ordered so the legal transitions can be expressed as "forward only", which
    is what keeps a retried request from moving a finished session backwards.
    """

    SCHEDULED = "scheduled"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    NO_SHOW = "no_show"


class NotificationType(StrEnum):
    """Why a notification exists, as the client switches on it.

    Every member has a producer in the service layer. A type with no producer is
    worse than a missing one: the client draws an icon and a deep link for a
    notification that can never arrive, and the one that does arrive has no
    case. Certificate and reminder events are deliberately absent until the code
    that raises them exists.
    """

    REQUEST_RECEIVED = "request_received"
    REQUEST_ACCEPTED = "request_accepted"
    REQUEST_DECLINED = "request_declined"
    SESSION_STARTED = "session_started"
    SESSION_COMPLETED = "session_completed"
    SESSION_CANCELLED = "session_cancelled"
    RATING_RECEIVED = "rating_received"
    PROMOTION = "promotion"

    #: The other party of a session wrote in the thread. One per quiet stretch,
    #: not one per line: see `notification_service.message_received` for why a
    #: bell row per "ok" would make the inbox useless.
    MESSAGE_RECEIVED = "message_received"


class RatingTag(StrEnum):
    """What a student may say about a tutor beyond the score.

    A fixed vocabulary, because the tags are read by other students choosing a
    tutor: free text at that position would be a public comment with no
    moderation, while a closed set is something the profile can render, count,
    and translate without a reporting queue behind it.

    Every tag is a claim about the session that just happened and one a student
    can make from memory. The set is deliberately all-neutral-to-positive and
    carries no negative member: the score is where dissatisfaction goes, and a
    "not prepared" chip beside a three is a second, sharper answer to a question
    the student already answered.

    Wire values are the bare lowercase name and are part of the contract. A tag
    removed from this enum is a breaking change for any client that still sends
    it; adding one is not, because an older client can display a tag it does not
    know from the value itself.
    """

    CLEAR_EXPLANATION = "clear_explanation"
    PATIENT = "patient"
    WELL_PREPARED = "well_prepared"
    MADE_IT_CLICK = "made_it_click"
    PRACTICAL_EXAMPLES = "practical_examples"
    ON_TIME = "on_time"


class DevicePlatform(StrEnum):
    """Where a push token came from.

    Stored so a future payload can be shaped per platform. The beta ships an
    Android APK, but the column is not Android-only: a token table that cannot
    hold the first iOS build is a migration on the day push is switched on.
    """

    ANDROID = "android"
    IOS = "ios"
    WEB = "web"


#: The only moves a session may make.
#:
#: Declared as data rather than scattered `if` statements in a service, so the
#: rule is stated once and can be asserted against directly. Terminal states
#: appear in no entry, which is what makes them terminal.
SESSION_TRANSITIONS: dict[SessionStatus, frozenset[SessionStatus]] = {
    SessionStatus.SCHEDULED: frozenset(
        {SessionStatus.IN_PROGRESS, SessionStatus.CANCELLED, SessionStatus.NO_SHOW}
    ),
    SessionStatus.IN_PROGRESS: frozenset(
        {SessionStatus.COMPLETED, SessionStatus.CANCELLED}
    ),
    SessionStatus.COMPLETED: frozenset(),
    SessionStatus.CANCELLED: frozenset(),
    SessionStatus.NO_SHOW: frozenset(),
}

#: States from which a session counts towards a tutor's hours and promotion.
#:
#: `NO_SHOW` is excluded on purpose: counting a session the tutor attended but
#: the student missed would let a tutor bank hours and reach promotion by
#: turning up to sessions that never happened.
COMPLETED_SESSION_STATUSES = frozenset({SessionStatus.COMPLETED})

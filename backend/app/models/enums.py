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
    """

    OPEN = "open"
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

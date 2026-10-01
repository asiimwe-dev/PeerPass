"""Account deletion, carried out as anonymisation rather than as a row removal.

Every FK to `users.id` cascades. A `DELETE` on the row would therefore take the
sessions, ratings, endorsements, competencies and `TutorProfile` with it, and
`Session` is the source of truth for a tutor's hours -- so deleting the row
would silently rewrite a colleague's `certified_minutes` and their certificate
eligibility. `User.deleted_at` already records the promise that the row stays, and
this module is what keeps it.

The split this module draws is between *identity*, which the person asked to stop
existing, and *evidence*, which other people's standing is computed from. The
identifying columns go; the evidence stays.

Two of the columns scrubbed here are judgement calls rather than personal data in
any obvious sense, so they are worth naming:

`university_id` and `faculty_id` are not, on their own, about a person -- but
"a third-year in the engineering faculty" re-identifies one in a cohort of nine,
and `university_id` also drops a tombstone out of tutor rail and matching, which
is where a deleted person has no business still appearing.

`academic_data_consented_at` is a timestamp of an event, not of a person, and it
is scrubbed anyway. A consent record exists to evidence that *a named person*
agreed to a specific processing; with the name and the address gone it evidences
nothing, and a request to erase is itself a withdrawal of the basis for
processing. The cost is that a later retention argument can no longer point at
this column to show the surviving competencies were lawfully obtained, and that
argument has to be made from `deleted_at` plus the competencies instead. If a
maintainer decides the consent record should outlive the consent, this is the one
line to drop.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import RefreshToken, User, set_roles

#: The domain a tombstone's rewritten address lands in.
#:
#: `.invalid` is reserved by RFC 2606 and is in no DNS zone, so this address can
#: never be delivered to, cannot resolve, and cannot be registered with somebody
#: else's domain.
DELETED_EMAIL_DOMAIN = "deleted.invalid"

#: A `password_hash` that no password can ever satisfy.
#:
#: Deliberately not a valid Argon2 hash of an unguessable secret. That would also
#: refuse every guess, but it would leave a real credential hash in the row and
#: would make `password_needs_rehash` report a healthy account, so the next
#: process to touch this column would treat a tombstone as a live one.
#:
#: `verify_password` gives it the same answer it gives a wrong password: not a
#: PHC string, so Argon2 raises `InvalidHashError`, which is caught and answered
#: by burning a decoy verification and returning `False`. Sign-in against a
#: tombstone therefore costs the same as sign-in against a bad password and is
#: indistinguishable from it, which is what stops the placeholder hash from
#: becoming an oracle that says "this account was deleted".
DELETED_PASSWORD_HASH = "!deleted-account"


def tombstone_email(public_id: uuid.UUID) -> str:
    """The address a deleted account's row is rewritten to.

    Unique because `public_id` is unique, so the unique index on `users.email`
    keeps two tombstones from colliding.

    Unclaimable in the stronger sense: Pydantic's `EmailStr` refuses the whole
    `invalid` TLD as a special-use name, so `POST /v1/auth/register` cannot even
    express this address. Registration rejects it with a validation error before
    any service runs, which means a new student cannot take the row over and
    cannot use the placeholder to infer which `public_id` belongs to anybody.
    """
    return f"deleted+{public_id}@{DELETED_EMAIL_DOMAIN}"


def _utcnow() -> datetime:
    return datetime.now(UTC)


async def delete_account(db: AsyncSession, user: User) -> None:
    """Anonymise `user` in place and commit.

    Safe to call twice. The rewritten email is derived from `public_id`, which
    never changes, and the password hash is a constant, so a second call writes
    the same values back rather than layering a second scrub on top; the token
    and role statements match nothing; and `deleted_at` is left at the instant the
    request was first received, because that timestamp is what a retention
    answer cites and it must not move when a client retries.

    Over HTTP the guard in `get_current_user` refuses a tombstone before this
    runs, so a retried `DELETE /v1/users/me` comes back 401 rather than a second
    204. Both end in the same place -- not signed in, account still anonymised --
    and distinguishing them would tell an attacker that a `public_id` had once
    been a live account.
    """
    now = _utcnow()

    user.email = tombstone_email(user.public_id)
    user.full_name = None
    user.password_hash = DELETED_PASSWORD_HASH
    user.year_of_study = None
    user.faculty_id = None
    user.university_id = None
    user.academic_data_consented_at = None

    # As well as the `deleted_at` check every guard now makes on its own. A
    # tombstone has to fail *closed* against code that has not been taught about
    # deletion yet, and `is_active` is what every existing access path reads. A
    # moderation process that later flips it back to True cannot resurrect the
    # account, because `deleted_at` is still set.
    user.is_active = False

    await _revoke_refresh_tokens(db, user.id, now)

    # Roles are dropped rather than scrubbed. A role is a grant, and a tombstone
    # has nobody to exercise one: leaving `student` behind would keep a deleted
    # account on tutor rails and in matching by way of a stale join row.
    await set_roles(db, user.id, set())

    if user.deleted_at is None:
        user.deleted_at = now

    await db.commit()


async def _revoke_refresh_tokens(
    db: AsyncSession, user_id: uuid.UUID, now: datetime
) -> None:
    """Retire every refresh token the account holds.

    Revoked rather than deleted, for the reason `auth_service.sign_out` gives:
    `replaced_by_id` is what makes a replay detectable as theft, and a row that
    no longer exists is a row the reuse walk cannot find. Already-revoked tokens
    are left alone, so each `revoked_at` records when that token actually died
    rather than when the account did.

    A single `UPDATE`, not a loop over the ORM objects, so this does not depend
    on the relationship having been loaded.
    """
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )

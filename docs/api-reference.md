# API Reference

The public HTTP contract. Every route lives under `/v1`, mounted in one place
(`backend/app/api/router.py`) so the prefix cannot drift between modules.

Base URL in development: `http://127.0.0.1:8000`.
Interactive schema: `/docs`.

## Conventions

**Identifiers.** Every identifier a client handles is a public UUID. No endpoint
returns a primary key, and a request taking an id takes that resource's *public*
id. A `public_id` is not a primary key and cannot be assumed sequential.

**Authentication.** Endpoints marked *auth* require
`Authorization: Bearer <access_token>`. The bearer token is checked for its type
as well as its signature, so a refresh token presented where an access token is
expected is a 401 rather than a 30-day session.

**No role claims in tokens.** Roles are read from the database on every request.
A suspended account's next request reflects that immediately instead of whenever
its access token happens to expire.

**Timestamps** are ISO 8601 with an offset, in UTC.

## Errors

Every error the API returns — framework validation, domain rejection, or an
unhandled fault — has the same body, [RFC 9457 problem details][rfc9457],
served as `application/problem+json`. The client has one shape to parse.

```json
{
  "type": "https://peerpass.app/problems/authentication_required",
  "title": "Authentication required",
  "status": 401,
  "detail": "That email or password is not right.",
  "instance": "/v1/auth/login",
  "code": "authentication_required"
}
```

| Field      | Notes                                                              |
| ---------- | ------------------------------------------------------------------ |
| `detail`   | Human-readable and **safe to show a student**. Never a stack trace, SQL fragment, or token. |
| `code`     | Stable machine-readable slug. Absent on the rare 4xx built directly from an `HTTPException`. |
| `errors`   | Field name → reason. **Present only on validation rejections** (422). |

The envelope is rendered once, in `backend/app/main.py`. A route raises; it never
builds an error body by hand.

### Status codes

| Status | `code`                  | When                                                        |
| ------ | ----------------------- | ----------------------------------------------------------- |
| 400    | `error`                 | Bad request, from an `HTTPException`.                        |
| 401    | `authentication_required` | Missing, expired, or wrong-type token; refused credentials. |
| 403    | `not_permitted`         | Authenticated but not allowed. Wording never names the internal reason. |
| 404    | `not_found`             | Absent, or not visible to this caller.                       |
| 409    | `conflict`              | Collided with existing state. Expected on a retried mobile request. |
| 422    | `validation_failed`     | One or more submitted values were rejected. Carries `errors`. |
| 500    | `internal_error`        | Unhandled fault. The cause is logged server-side; the body says nothing about it. |

## Auth

### `POST /v1/auth/register`

Create an account. **201.** No auth.

An account is an email and a password and nothing else. The name, faculty, and
year are collected by the onboarding wizard that runs immediately afterwards,
which is a separate screen a student can leave and come back to.

```json
{
  "email": "student@must.ac.ug",
  "password": "a-long-enough-password"
}
```

Responses `201` with tokens and the new account in one body, so the client never
holds a valid token it cannot yet render a name for.

**Errors**

| Status | `detail`                                             |
| ------ | ---------------------------------------------------- |
| 409    | `An account already exists for that email address.`  |
| 422    | `That password cannot be accepted.` — the reason is in `errors.password` |

The password is 8–128 characters, must not be entirely whitespace, and is
checked against a common-password deny-list. The reason is returned as
`errors.password`, e.g. `Password must be at least 8 characters long.`,
`That password is too common. Choose something longer that is not a dictionary
word or a keyboard pattern.`

Lowering the minimum to 8 cannot invalidate an existing password: this endpoint
creates accounts, and `POST /v1/auth/login` enforces no minimum at all (only the
128 maximum), so a password accepted under the old 12-character rule keeps
working.

A new account has `full_name: null` and holds only the `student` role. The tutor
role is not grantable at registration; it is earned by declaring a grade and
having that competency verified.

### `POST /v1/auth/login`

Exchange credentials for a token pair. No auth.

```json
{
  "email": "student@must.ac.ug",
  "password": "a-long-enough-password"
}
```

**Errors**

| Status | `detail`                                       |
| ------ | ---------------------------------------------- |
| 401    | `That email or password is not right.`         |
| 422    | Field-level, from the request schema.          |

An unknown address and a wrong password produce the **same** 401, the same body,
and the same work. A decoy Argon2 verification runs when the account is not
found, so response time does not distinguish the two cases. This is deliberate:
the pilot's realistic attacker holds a list of student addresses, and telling
them which of them have an account hands over half the target.

### `POST /v1/auth/refresh`

Exchange a refresh token for a new pair. No auth — the token is the credential.

```json
{ "refresh_token": "..." }
```

**The client must replace its stored refresh token with the one in this
response.** The token just sent stops working the moment this returns; sending
it a second time is treated as theft and revokes the entire chain.

Refresh tokens live 30 days and rotate on every use. Presenting an already-used
token revokes the family, so a stolen token is usable at most once and its use
signs out the legitimate device too.

### `POST /v1/auth/logout`

Revoke the caller's refresh token. *Auth.* **204**, no body.

The body is optional:

```json
{ "refresh_token": "..." }
```

**204 whether or not a token was presented.** Sign-out is what the student asked
for, and refusing because the server had not heard of the token would leave
someone unable to end a session on a device that lost its state. A client that has
already cleared its token store can still sign out cleanly.

### `GET /v1/auth/me`

The caller's own record. *Auth.*

The **only** endpoint that returns `academic_data_consented_at`. `UserResponse`
deliberately has no consent field, so no other route can leak it by accident.

## Users

### `PATCH /v1/users/me`

Apply an onboarding step. *Auth.* Returns the updated record in the same shape
as `GET /v1/auth/me`, consent timestamp included, because the client needs the
stored `academic_data_consented_at` to know its own grant was recorded.

Every field is optional and an absent one is left alone, because the wizard saves
each step as it is completed. A step sending only `full_name` must not blank the
faculty picked a moment earlier, and a retried step must be safe to send twice.
This is why it is `PATCH` and not `PUT`: a `PUT` would have to require the whole
profile, so a step not yet reached would be sent as `null` and erase what an
earlier step had just saved.

| Field                    | Type          | Notes                                                |
| ------------------------ | ------------- | ---------------------------------------------------- |
| `full_name`              | string \| null | 2–160 characters after trimming.                     |
| `university_id`          | UUID \| null  | Public id.                                          |
| `faculty_id`             | UUID \| null  | Public id of a `subject`. See [Faculties are subjects](#faculties-are-subjects). |
| `year_of_study`          | int \| null   | 1–6.                                                |
| `academic_data_consented` | bool \| null | `true` records consent. **Never withdraws it.**      |

A field is cleared by sending an explicit `null`, which is what makes the partial
update unambiguous.

`academic_data_consented: true` stamps `academic_data_consented_at` **once** and
never moves it. Consent cannot be withdrawn through this field: the Uganda Data
Protection and Privacy Act requires a withdrawal to be as express as the original
grant, and to be logged.

**Errors**

| Status | `detail`                        | `errors`                          |
| ------ | ------------------------------- | --------------------------------- |
| 404    | `That university could not be found.` |                                |
| 404    | `That faculty could not be found.`    |                                |
| 422    | `Some of the details you entered are not valid.` | Keyed by field name. |

## Academics

Read-only, administrator-loaded reference data. No create, update, or delete: a
student who could invent a course unit their own transcript never mentioned could
manufacture a match for it.

**All three are unauthenticated.** The sign-up form shows a student where they
study before they have an account, and a published faculty list leaks nothing a
prospectus does not.

### `GET /v1/academics/universities`

Every institution, alphabetically. `grading_scale_id` is nullable: a tutor cannot
be matched until their university has a scale, and the matching service reports
that rather than assuming one.

```json
[
  {
    "id": "8e2c…",
    "name": "Makerere University",
    "grading_scale_id": "1f4a…"
  }
]
```

### `GET /v1/academics/faculties`

Every faculty, alphabetically. Returns `[{ "id": …, "name": … }]`.

#### Faculties are subjects

`GET /faculties` returns rows from `subjects`, and `PATCH /users/me` stores
`faculty_id` as a `subjects` public id. A faculty is a property of a course unit
rather than of an institution, so the list is global.

**Consequence to know about before seeding a second university:**
`subjects.name` is globally unique and `subjects` has no `university_id`. Two
universities cannot currently have a subject with the same name, and the list
cannot be filtered per university. Lifting this means moving ownership —
`subjects` gets a nullable `university_id`, the unique constraint becomes
`(university_id, name)`, and `/faculties` takes a `university_id` filter. The
university-first pilot hides this; a multi-institution deployment will not.

### `GET /v1/academics/course-units`

Course units, optionally narrowed to one faculty. Ordered by university, then by
code — a student scanning for `BIT 221` is looking for a code, not for
alphabetical position.

| Query        | Type | Notes                                                     |
| ------------ | ---- | --------------------------------------------------------- |
| `subject_id` | UUID | Optional. A faculty **public** id.                       |

A malformed `subject_id` is a 422 from FastAPI, not a silently empty list. An
unrecognised but well-formed one returns `[]`: the client filtered on a value it
believed exists, and the honest answer to "units in this faculty" is "none". A
404 would put the wizard into an error state for something the student did not do.

This is the endpoint onboarding's **third** step will use. The step is not built:
matching cannot act on a declared unit yet, and the API has nothing to match
against until the matching slice lands.

## Health

### `GET /health`

`{"status": "ok"}`. Deliberately does **not** touch the database — a liveness
probe that fails when Postgres is briefly unavailable will restart the process,
turning a database blip into an outage.

## Data model notes

**An account exists before it has a name.** `users.full_name` is nullable, and
`needsOnboarding` on the client is `full_name` null-or-blank **or** `university_id`
null. A nameless account is not an error state; it is the state a student is in
between finishing sign-up and finishing the wizard.

**`User` and `UserResponse`** differ in what they expose. `UserResponse` has no
`password_hash` and no `password_hash` field exists anywhere in the schemas
package; adding the attribute is one line and nothing fails until someone reads a
payload. `UserResponse` also has no consent timestamp, because another user's
consent is not the caller's to see.

[rfc9457]: https://www.rfc-editor.org/rfc/rfc9457

# PeerPass Architecture

**System Design & Technical Blueprint**

> This document describes the high-level architecture, core components, data model, matching engine, and validation protocol of PeerPass — a peer-to-peer academic support network for university students.

**Last Updated**: September 2026 | **Status**: Active

---

## 1. Vision & Design Goals

PeerPass exists to replace the “attend lectures and fight for your life” model with a reliable, stigma-free micro-intervention safety net. The architecture is shaped by the following goals:

| Goal                        | Architectural Implication                                                           |
| --------------------------- | ----------------------------------------------------------------------------------- |
| Mobile-first, low-bandwidth | Flutter client; lightweight API payloads; offline-friendly patterns where practical |
| Academic integrity          | Multi-tier tutor validation before matching is allowed                              |
| Low friction for students   | Simple request → match → session flow                                               |
| Verifiable incentives       | Session logging that can generate Teaching Assistant certificates                   |
| Institutional readiness     | PostgreSQL relational model, SSO-ready auth, DPPA-compliant data handling           |
| Future LMS integration      | Clean API boundaries and modular services                                           |

---

## 2. High-Level System Overview

```
┌─────────────────┐         HTTPS / REST          ┌──────────────────────┐
│                 │  ◄──────────────────────────► │                      │
│  Flutter App    │                               │   FastAPI Backend    │
│  (Mobile)       │                               │                      │
│                 │                               │  • Auth & Users      │
└─────────────────┘                               │  • Matching Engine   │
                                                  │  • Validation        │
                                                  │  • Sessions & Ratings│
                                                  │  • Incentives        │
                                                  └──────────┬───────────┘
                                                             │
                                                             │ SQLAlchemy
                                                             ▼
                                                  ┌──────────────────────┐
                                                  │    PostgreSQL        │
                                                  │                      │
                                                  │  Users               │
                                                  │  Course_Units        │
                                                  │  Competencies        │
                                                  │  Help_Requests       │
                                                  │  Sessions            │
                                                  │  Ratings             │
                                                  └──────────────────────┘
```

**Key characteristics**

- Client-server architecture with a single mobile client (Flutter)
- Stateless REST API (FastAPI) for all business logic
- Relational database as the source of truth for users, competencies, and sessions
- Matching and validation logic live in dedicated backend services (not in the client)

---

## 3. Technology Stack

| Layer                | Technology                  | Rationale                                                                                                    |
| -------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Frontend**         | Flutter                     | Cross-platform (Android + iOS), excellent performance on modest devices, strong offline capabilities         |
| **Backend**          | FastAPI (Python 3.10+)      | High performance, automatic OpenAPI docs, excellent async support, rapid development                         |
| **ORM / Migrations** | SQLAlchemy + Alembic        | Mature, type-friendly, reliable schema evolution                                                             |
| **Database**         | PostgreSQL                  | Strong relational integrity, excellent for complex joins (matching + competencies), JSON support when needed |
| **Auth**             | JWT + future University SSO | Stateless tokens for mobile; designed for institutional SSO integration                                      |
| **API Style**        | RESTful JSON                | Simple, cacheable, easy to consume from Flutter                                                              |

---

## 4. Core Components

### 4.1 Frontend (Flutter)

Organized in a **feature-first** structure:

- `auth` — Registration, sign-in, and the onboarding wizard
- `home` — The signed-in hub. Phase 2 ships it as an honest empty state
- `profile` — Student / tutor profile & role management _(planned)_
- `matching` — Create topic requests, view matches, accept/reject _(planned)_
- `sessions` — Schedule, join, and complete micro-sessions _(planned)_
- `tutor_validation` — Upload transcript / link portfolio, view verification status _(planned)_
- `incentives` — View logged hours and certificate status _(planned)_

Shared layers:

- Network client (Dio), failures, and RFC 9457 translation
- Riverpod for state management
- Core theme, constants, and reusable widgets

#### Session state lives in `core/`, not in `auth`

`frontend/lib/core/state/session.dart` holds the one source of truth for who is
signed in. This is not a layering preference, it is forced by two rules in
`AGENTS.md`: a feature must never import another feature's `presentation/`, and
`core/` must never import from `features/`.

Home has to know who is signed in, and the router has to decide where a session
belongs. If the session lived in `auth`'s presentation layer, both would be
either an illegal import or a rule exception. Promoting it to `core/` gives one
place that auth writes and that the router and every feature can read, with no
rule changed. `UserProfile` moved to `core/models/` for the same reason — it is
consumed by several features, so a feature-local home for it was always going to
be wrong.

The consequence worth stating: `AuthController` no longer holds state. It
performs repository calls and records the outcome in the core session, so there
is exactly one `SessionState` and no second copy to fall out of step.

#### The repository provider is declared with the contract

`authRepositoryProvider` is declared in
`frontend/lib/features/auth/data/repositories/auth_repository.dart`, not in the
feature's presentation layer. A provider declared in `presentation/` could not be
imported by a sibling feature without dragging that feature's screens along, so
the handle has to sit beside the interface it hands out.

This is the one cross-feature import the architecture permits, and home's
sign-out uses it (`features/home/presentation/providers/sign_out_controller.dart`):
it calls the auth repository contract and records the outcome in the core
session. `test/architecture/dependency_rules_test.dart` enforces exactly this
line — another feature's `presentation/` is forbidden, its repository contract
is not.

#### Composition happens in `main.dart`, once

`lib/main.dart` is a real composition root: `AppConfig`, `SecureTokenStore`,
`RemoteAuthRepository`, and the remote datasources are built there and overridden
into `ProviderScope`. There is no in-memory default on the request path, so a
stub cannot hide behind a working screen.

#### Validation is deliberately duplicated

`frontend/lib/core/utils/validators.dart` repeats the server's rules rather than
the server being the only enforcer. The server stays the authority; the client
checks only to spare a round trip and to put a message under the input that
caused it. A client-side rule that drifts from the server is a cosmetic bug, not
a security hole.

#### Animations are native and finite

Splash, sign-in, sign-up, and the consent tick are custom-painted. No Rive, no
animation package, no image assets. They are also finite rather than looping, so
`pumpAndSettle()` terminates in a widget test and the app is not burning a
timeline forever behind a static screen. All of them respect
`MediaQuery.disableAnimations`.

### 4.2 Backend (FastAPI)

Layered structure:

```
api/          → HTTP routes & request validation
services/     → Business logic (matching, validation, incentives)
models/       → SQLAlchemy ORM models
schemas/      → Pydantic request/response models
core/         → Config, security, database session, exceptions
```

**Critical services**

- `MatchingService` — Core algorithm that pairs tutee requests with eligible tutors
- `ValidationService` — Implements the three-tier tutor quality gate
- `SessionService` — Lifecycle of a tutoring session + logging
- `IncentiveService` — Aggregates hours and prepares certificate data

### 4.3 Database (PostgreSQL)

Primary tables (see Section 5 for details):

| Table               | Responsibility                                                   |
| ------------------- | ---------------------------------------------------------------- |
| `users`             | Identity and contact details; roles live in the `user_roles` join |
| `user_roles`        | A user's roles, which may be several (`student` and `tutor`)      |
| `refresh_tokens`    | Hashed refresh-token handles, for rotation and reuse detection    |
| `universities`      | Institution a user and course unit belong to                       |
| `grading_scales`    | An institution's scale and its competency threshold               |
| `grades`            | The grade catalogue for a scale                                   |
| `subjects`          | Faculty or department grouping for course units                   |
| `course_units`      | University curriculum mapping                                     |
| `competencies`      | Tutor eligibility per course unit (grade + verification status)   |
| `tutor_profiles`    | A tutor's standing and the counters it is derived from            |
| `help_requests`     | What a student asked for, before any tutor was matched            |
| `sessions`          | A tutoring session that actually took place                       |
| `ratings`           | Post-session feedback that drives tutor promotion / demotion     |

### 4.4 Transport Schemas (`backend/app/schemas/`)

Pydantic v2 models, separated from the ORM, so the wire contract can change
without a migration and the tables can change without a client release.

Two base types carry the whole policy:

- `RequestSchema` — `extra="forbid"`. A misspelled field is an error rather than
  a silent drop, because a `rating` sent as `score` would otherwise create a
  rating with no score.
- `OrmSchema` — `from_attributes`, `frozen`, `populate_by_name`.

**Internal keys never reach the wire.** A response field named `id` is populated
from the model's `public_id` through `validation_alias`, and a referenced
resource is named the same way:

| Response field          | Read from                      |
| ----------------------- | ------------------------------ |
| `id`                    | `public_id`                    |
| `course_unit_id`        | `course_unit_public_id`        |
| `university_id`         | `university_public_id`         |
| `grading_scale_id`      | `grading_scale_public_id`      |
| `user_id` (tutor)       | `user.public_id`               |

This is not a convention to remember, it is a test:
`backend/tests/schemas/test_public_id_projection.py` resolves every alias
against the real mapped class and fails on a `*_id` field that has no alias —
which is the shape of a primary key quietly shipping to a client.

**Not every response can be built straight from a query.** These fields need a
service, and the test file lists them so each one is a deliberate edit:

| Field                  | Why                                                        |
| ---------------------- | ---------------------------------------------------------- |
| `UserResponse.roles`   | `user_roles` is an association table, not a relationship   |
| `SessionResponse.is_rated` | `Session.is_rated(db)` is an async query hook           |
| `CompetencyResponse.meets_threshold` | A method taking the threshold, not a field |
| `CompetencyResponse.grade_points`    | Computed in the service                 |

**Decimals cross the wire as JSON strings.** Pydantic's default, kept
deliberately: a JSON number is a double in Dart, and a double cannot represent
every `numeric(6,2)` value, so `rating_total` is `"18.00"` and not `18.0`. The
client parses it for display; every threshold comparison happens server-side
against the `Decimal`.

**Trimming is per field, not per model.** `app.schemas.base.Trimmed` is applied
to names, topics, and feedback, and deliberately *not* to passwords, whose
leading and trailing spaces are part of the secret.

---

## 5. Data Model

### 5.1 Entity Relationships (Conceptual)

```
Universities 1 ─── * Grading_Scales 1 ─── * Grades
      │ 1                │ 1
      │                  │
      │ *                │
Course_Units * ─────────┘ (grade)
      │ *
      │ 1
      │
Users 1 ─── * Competencies
  │ 1
  │
  ├── 1 Tutor_Profiles
  ├── * Help_Requests * ─── * Sessions * ─── * Ratings
  └── * Refresh_Tokens
```

`help_requests` and `sessions` are separate tables on purpose. A request that is
never matched must not leave a session row behind, or every tutor workload query
carries a filter for sessions that never happened.

### 5.2 Schema Highlights

| Table             | Core Attributes                                                | Purpose                                                                                |
| ----------------- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Users**         | `id`, `public_id`, `email`, `full_name`, `university_id`, `faculty_id`, `year_of_study` | Identity. Roles live in `user_roles`, because one user may be both student and tutor. `full_name` is **nullable**: an account exists between sign-up and the end of onboarding, and requiring a name at registration would put four fields on the sign-up form to get the same result — the first one lost is a student who abandons it |
| **User_Roles**    | `user_id`, `role`                                              | Join table; composite primary key stops a role being held twice                         |
| **Tutor_Profiles**| `user_id`, `standing`, `rating_total`, `rating_count`, `certified_minutes` | Aggregate standing, stored rather than recomputed per matching query          |
| **Grading_Scales**| `max_points`, `competency_min_points`                          | The B+ bar as data, since pilot institutions disagree on what B+ means                 |
| **Grades**        | `label`, `grade_points`, `grading_scale_id`                    | Grade catalogue; one label per scale                                                    |
| **Course_Units**  | `code`, `name`, `university_id`, `subject_id`, `grade_id`      | Maps the exact university curriculum                                                    |
| **Competencies**  | `user_id`, `course_unit_id`, `grade_id`, `status`, `source`    | Validation gate requiring a verified grade at or above the scale's threshold            |
| **Refresh_Tokens** | `id` (PK), `user_id` (FK → users), `token_hash` (unique), `expires_at`, `revoked_at`, `replaced_by_id` (FK → refresh_tokens, optional) | The handle is a JWT; only its peppered hash is stored, so a database disclosure yields no usable token. `replaced_by_id` forms the chain that makes reuse of an already-rotated token detectable. Every row is deleted on user deletion |

##### A known limitation: `subjects` is global

`users.faculty_id` points at `subjects`, because a faculty is a property of a
course unit rather than of an institution. The consequence is that
`subjects.name` is **globally unique** and `subjects` carries no
`university_id`. So `GET /v1/academics/faculties` is a global list, and two
universities cannot have a subject with the same name.

A single-institution pilot hides this. A multi-institution deployment will not,
and it will be discovered by a seed failure rather than by reading this. Lifting
it: give `subjects` a nullable `university_id`, change the unique constraint to
`(university_id, name)`, and add a `university_id` filter to `/faculties`.

**Help_Requests** | `tutee_id`, `course_unit_id`, `topic`, `status`                | What was asked for, before a tutor was matched                                          |
| **Sessions**      | `tutee_id`, `tutor_id`, `course_unit_id`, `status`, `duration_minutes`, `session_pin`, `meeting_link` | A session that happened; the source for tutor hours and certificates. Includes PIN for handshake and copyable meeting link |
| **Ratings**       | `session_id`, `rater_id`, `ratee_id`, `score`, `feedback_text` | Post-session feedback; low ratings reduce matching priority                           |

### 5.3 Detailed Table Definitions

Every table uses a UUIDv7 `id` primary key and a separate UUIDv4 `public_id` for
the wire. The primary key is time-ordered so inserts land at the end of the write
index; the public id is random so it encodes nothing about creation time.

**Users**

- `id` (PK), `public_id` (unique)
- `email` (unique), `full_name`, `password_hash`
- `university_id` (FK → universities, optional)
- `is_active`
- `academic_data_consented_at` — records the academic-data consent the Uganda
  Data Protection and Privacy Act requires before a transcript is processed
- Roles are **not** a column. See `user_roles`.

**User_Roles**

- `user_id` (FK → users), `role` — `student` | `tutor`
- Composite primary key on (`user_id`, `role`)

There is deliberately no `admin` role. Administrator access is not modelled yet,
and a role that grants it would need audit logging attached before it is worth
having; adding the string to the enum now would make it look implemented.

**Universities**

- `id` (PK), `name` (unique)
- `grading_scale_id` (FK → grading_scales) — required before a tutor at this
  institution can be matched

**Grading_Scales**

- `id` (PK), `name` (unique), `max_points`
- `competency_min_points` — the lowest grade that makes a tutor eligible, in
  this scale's points
- CHECK: `0 < competency_min_points <= max_points`

**Grades**

- `id` (PK), `label`, `grade_points`, `max_points`
- `grading_scale_id` (FK → grading_scales)
- Unique on (`grading_scale_id`, `label`)
- CHECK: `0 < grade_points <= max_points`
- `max_points` is denormalised from the scale so the CHECK above can be enforced
  by the database, which cannot compare across tables. Rescaling a published
  scale must rescale its grades in the same transaction.

**Subjects**

- `id` (PK), `name` (unique)
- A faculty or department grouping. Distinct from a course unit: matching widens
  from a unit to its subject, so a tutor can be competent across several units.

**Course_Units**

- `id` (PK), `code`, `name`, `description`
- `university_id` (FK → universities) — **required**
- `subject_id` (FK → subjects), `grade_id` (FK → grades), both optional
- Unique on (`university_id`, `code`)

`university_id` is required because a composite unique index treats NULLs as
distinct, so a nullable university would let two unscoped units share a code. It
is also required by matching, which only pairs people at one institution.
Scoping the code is what lets `MAT 221` exist at two universities as two
different courses, graded on two different scales.

**Competencies**

- `id` (PK)
- `user_id` (FK → users), `course_unit_id` (FK → course_units)
- `grade_id` (FK → grades)
- `status` — `pending` | `verified` | `rejected`
- `source` — `transcript` | `portfolio` | `manual`
- `reviewed_by_id` (FK → users), `verified_at`, `rejection_reason`,
  `evidence_reference`
- Unique on (`user_id`, `course_unit_id`)

Both `user_id` and `reviewed_by_id` point at `users`, so the ORM relationships
must name their foreign key explicitly. A pending competency never meets the
threshold, whatever grade it carries: a grade is a claim until checked.

**Tutor_Profiles**

- `id` (PK), `user_id` (FK → users, unique)
- `standing` — `probationary` | `verified` | `reduced` | `suspended`
- `completed_sessions`, `certified_minutes`
- `rating_total`, `rating_count` — a running total and a count, not a stored
  average, so promotion does not accumulate rounding error on an equality test
- `suspended_reason`

**Help_Requests**

- `id` (PK)
- `tutee_id` (FK → users), `course_unit_id` (FK → course_units)
- `topic`, `description`
- `status` — `open` | `matched` | `withdrawn` | `expired`
- `matched_tutor_id` (FK → users, optional)

**Sessions**

- `id` (PK)
- `tutee_id`, `tutor_id` (FK → users) — CHECK: `tutee_id <> tutor_id`
- `course_unit_id` (FK → course_units), `help_request_id` (FK → help_requests,
  optional and unique)
- `topic`, `scheduled_start`, `started_at`, `ended_at`, `duration_minutes`
- `status` — `scheduled` | `in_progress` | `completed` | `cancelled` | `no_show`
- `cancelled_by_id` (FK → users), `cancellation_reason`
- CHECK: `duration_minutes >= 0`
- CHECK: a `completed` session has both `started_at` and `ended_at`, since
  otherwise the hours it contributes to a certificate are unknowable

**Ratings**

- `id` (PK)
- `session_id` (FK → sessions), `rater_id`, `ratee_id` (FK → users)
- `score` — CHECK: `1 <= score <= 5`
- `feedback_text`
- Unique on (`session_id`, `rater_id`), so a retried submit updates rather than
  averaging a second score in
- Used by the validation engine to promote or demote tutors

The rule that a completed session requires a rating spans two tables and cannot
be a CHECK constraint, which may only reference its own row. It is enforced in
the session service, and `Session.is_rated(db)` is the check it is written
against.

---

## 6. Multi-Tiered Tutor Validation Protocol

A peer-to-peer system is only useful if tutors are competent. PeerPass enforces quality through three sequential gates:

### Tier 1 — Academic Data Gate (Hard Gate)

- Tutor must have a verified grade of **B+ or higher** in the target course unit.
- Source: uploaded transcript or secure institutional query.
- Without this, the user cannot be matched as a tutor for that unit.

### Tier 2 — External Portfolio Gate (Practical Gate)

- Optional override / enhancement for practical subjects.
- Examples: GitHub activity for software modules, deployed projects, etc.
- Allows provisional elevation when traditional grades under-represent skill.

### Tier 3 — Probationary Feedback Loop (Community Gate)

- New tutors start at standing `probationary`.
- Every completed session requires a rating from the tutee.
- High average rating → standing `verified` + leadership credits.
- Low average rating → standing `reduced` (lower matching priority) or
  `suspended` (revoked for that unit).

Standing lives in `tutor_profiles.standing`, not in the user's role. The role says
what a person may do; the standing says how much they are trusted. Collapsing the
two into one column, as the earlier draft did with `role_type`, would make a
suspension indistinguishable from a role change and would lose the per-unit
revocation this tier exists to express.

This logic lives in `ValidationService` and is consulted by `MatchingService` before any match is proposed.

---

## 7. Matching Engine

### High-Level Flow

1. Tutee submits a **topic request** (course unit + specific concept).
2. System queries `Competencies` for tutors who:
   - Have verified (or provisional) status for that unit
   - Meet the current rating threshold
   - Are available / not overloaded
3. Ranking may consider:
   - Verification tier (verified > provisional)
   - Average rating
   - Number of completed sessions in the unit
   - Recency of activity
4. Top candidate(s) are presented to the tutee (or auto-matched, depending on configuration).
5. Once accepted, a `Session` is created and the scheduling flow begins.

The matching service is deliberately kept pure (no UI concerns) so it can later be exposed to institutional dashboards or LMS plugins.

---

## 8. Session Lifecycle

```
Request Created
      │
      ▼
Matching Engine runs
      │
      ▼
Tutor Accepts / Declines
      │
      ▼
Session Scheduled (in-app)
      │
      ▼
Session Completed
      │
      ▼
Rating Submitted → ValidationService updates tutor status
      │
      ▼
IncentiveService logs hours → certificate eligibility
```

---

## 9. Security & Compliance

The pilot's threat model is specific: an attacker holding a list of student email
addresses, or a stolen copy of the database. Every choice below is aimed at one of
those two, and the reasoning is recorded so a later change can be judged against
it rather than re-argued from scratch.

> **Status: the primitives are built; the endpoints that enforce them are not.**
> Everything in 9.1–9.3 and 9.5 is implemented and unit-tested in
> `app/core/security.py`, `app/core/password_policy.py` and
> `app/core/config.py`. `app/api/v1/auth.py`, `app/services/auth_service.py` and
> `app/api/deps.py` are still empty, so **none of it is on a request path yet.**
> `denial_reason`, `hash_password`, `verify_password`, `create_token_pair` and
> `decode_token` currently have no production caller. Read this section as the
> contract those endpoints must satisfy, not as a description of live
> enforcement. Until they exist, there is no sign-in and no stored credential.

### 9.1 Secrets

Three independent secrets, none with a default, all required at startup. The API
refuses to boot without them, because an API that boots with no signing key will
happily issue tokens that nobody can revoke, and one that boots with no pepper can
be checked offline against a stolen database.

| Setting                 | Protects                                     | Rotating it                              |
| ----------------------- | -------------------------------------------- | ---------------------------------------- |
| `JWT_SECRET`            | Signs access tokens                          | Invalidates every issued token unless the old key is in `JWT_PREVIOUS_SECRETS` |
| `JWT_PREVIOUS_SECRETS`  | Verifies tokens signed by retired keys       | Removes the ability to verify old tokens |
| `TOKEN_PEPPER`          | Server-side key for hashing opaque tokens    | Signs every user out; no stored hash matches |

They are separate settings rather than one secret reused, because they protect
different things and rotate for different reasons. Sharing a value would mean one
compromise reaches all three, and rotating one would take the others out.

Placeholder values (`changeme`, `secret`, `replace-me`) and values under 32
characters are rejected. A committed placeholder reaches production more often
than anyone expects, and a warning in a `.env.example` is not a control.

### 9.2 Password storage

Argon2id at the OWASP minimum: 19 456 KiB, 2 passes, 1 lane. The floor is enforced
as a *validation bound in the settings model*, not only by a test, so it cannot be
lowered by an environment variable. Lowering a constant is visible in review;
lowering a config value in a deployment manifest is not.

Raising the parameters is not a migration. Every stored hash encodes the
parameters it was created with, and a successful sign-in transparently rewrites a
hash made under weaker settings, so a raised floor reaches existing accounts
gradually on their own.

Two properties that the auth service must implement matter for an attacker with a
stolen database. Both are available in `app/core/security.py` and neither is
called yet:

- **No PBKDF2 fallback.** A stored `pbkdf2_sha256$` hash is refused outright rather
  than verified. There is no PBKDF2 data in production to preserve, so supporting
  it would only create a weaker path to keep alive.
- **Uniform cost per guess.** An unknown email runs a decoy Argon2 verification
  against a random hash, so "no such user" and "wrong password" cost the same.
  A stored value that is malformed — not a PHC string, or one that names the right
  algorithm but cannot be parsed — is paid for explicitly, because those paths
  fail *before* any Argon2 work happens and would otherwise return measurably
  faster than a wrong password.

### 9.3 Password acceptance

Length-based, **8 to 128** code points, with no composition rules. Character-class
requirements are well documented to produce `Passw0rd!` — a predictable
substitution that satisfies the rule and is weaker than a passphrase of the same
length. The 128 ceiling exists so that a future move to bcrypt, which truncates at
72 bytes silently, cannot quietly reduce a long password to its first 72
characters.

**The floor was twelve and is now eight.** The reasoning matters, because a long
floor looks like the safer choice and is not. Past about eight characters students
stop inventing and start satisfying — they write `Password1!` and forget it, or
abandon the form. A longer floor therefore rejects honest students without
rejecting attackers, because every guess worth making is short: nobody
brute-forces a twelve character space when the useful guesses are eight characters
and known. The deny-list, not the floor, is what rejects attacker guesses, and
Argon2id's 19 MiB cost is what makes each one expensive.

**The residual risk is that there is no rate limiting on sign-in** (see 9.8), so
the number of guesses is unbounded and the deny-list is the only thing between a
leaked student address and a guessed password. This is a pre-existing gap that a
short floor makes load-bearing rather than theoretical. Rate limiting on
`/v1/auth/login` and `/v1/auth/register` is the correct next control, and it is
preferable to raising the floor back, because it addresses the actual threat
without the cost to the student.

A small static deny-list covers the passwords that would otherwise make the
Argon2 cost affordable. It is checked at **registration and password change only,
never at sign-in**: a student who chose a password that later lands on a breach
list must still be able to get into their own account, or anyone could lock them
out by reporting their password as common. That is the only place a deny-list is
safe.

The list is static and small on purpose, and is enforced by
`app/core/password_policy.py`, which the registration endpoint must call. A live
breach-API lookup would hand a third party a list of student addresses to check and
would make account creation depend on someone else's uptime. Keeping it short
enough to audit by eye is what makes it a control rather than decoration; it needs a
manual refresh, and that is a known cost rather than an oversight.

The cost of a static list is that it only covers what someone thought to add, and
at a floor of eight a student can reach a keyboard run the list never anticipated.
Entries are therefore listed in **base form**, because `denial_reason` strips
trailing digits and punctuation before the lookup: listing `asshole` refuses
`asshole1` and `asshole!` without naming either, and listing `1q2w3e4r` already
covers the trailing digits of its own longer variants. The list still has holes —
`tests/core/test_password_policy.py` pins the ones found so far, and a new one is
found by trying one, not by a control failing. That is the argument for rate
limiting.

### 9.4 Tokens

- **Access** — JWT, HS256. Carries `sub` (the `public_id`), `type`, `iat`, `exp`
  and `jti`. Nothing else. Roles are **not** in the token; they are read per
  request, so a role change takes effect immediately instead of at the next
  token refresh.
- **Refresh and email verification** — opaque random strings. Only a
  peppered HMAC-SHA256 of the token is stored, so a stolen database yields no
  usable token and no offline attack is possible, because the server-side pepper
  is not in the database.
- **No clock-skew leeway** is configured. A phone whose clock is a few seconds
  behind is signed out rather than tolerated. With a 15 minute lifetime the
  stricter failure is the one worth having, and a leeway setting is deliberately
  absent until a real device demonstrates a need for it.

Symmetric signing is deliberate. Asymmetric signing buys key separation between
issuer and verifier, which matters when a third party must check a token the
issuer cannot mint. That is not this service: it mints and verifies its own
tokens, so rotation is handled by a key set rather than a new key pair. The
saving is that `cryptography` — a compiled wheel of several megabytes — is not
shipped for a capability not in use.

`public_id` rather than the primary key is the `sub` because a UUIDv7 encodes its
creation time, and a leaked primary key would otherwise date and help enumerate
every other record.

Refresh tokens **rotate on every use**. Each exchange issues a new token and
records `replaced_by_id` on the one presented, so the table holds a chain.
Presenting a token that has already been replaced is treated as theft and
revokes the whole family, which signs out the attacker's device and the
legitimate one together. The cost is real: a client that retries a refresh
without storing the new token revokes its own session. That is the correct
trade, because the alternative — tolerating reuse — makes a stolen 30-day token
indefinitely renewable.

The consequence for the client is that **`/v1/auth/refresh` must replace the
stored refresh token with the one in its response.** The token just sent stops
working the moment the response returns.

#### Cold start

The access token lives in memory only, so a cold start has no access token and
must hold the splash screen until it has one. The order matters and is fixed:

1. Read the refresh token from secure storage. Nothing there → the session is
   simply unauthenticated, and this is not an error.
2. Exchange it for a pair, replacing the stored refresh token.
3. `GET /v1/auth/me` for the profile.

A network failure at step 2 or 3 keeps the user on the splash screen **with a
retry**; it does not report them as signed out, because "we could not reach the
network" and "your session ended" are different facts and only one of them is
true. A refresh that is *refused* does clear the token and routes to sign-in.

### 9.5 Logging

- `database_echo` logs SQL **with its bound parameters**, which for this schema
  means email addresses and password hashes. It is refused at startup unless
  `environment` is `development`.
- The frontend transport interceptor logs method, path, status and timing only.
  Headers and bodies are suppressed: headers carry the bearer token, and every
  body in this API is either a credential or a student's academic record.
- Unhandled server errors log the path and a fixed client-facing message.
  Interpolating an unexpected exception's message is how connection strings and
  row contents end up in a student's error toast.

### 9.6 Data protection

- Compliant with the Uganda Data Protection and Privacy Act, 2019 (DPPA). Grades
  and transcripts require explicit consent and secure storage.
- Access tokens are held in memory only and are never written to
  `shared_preferences`. The refresh token is the only secret persisted, and only
  in platform secure storage.
- The client never sees a row's primary key.
- **Transcript storage**: Uploaded verification proofs (Tier 1) are stored securely on the local filesystem of the backend. Only authorized admins and the system can access the raw paths stored in the database.

### 9.7 Schema changes

Alembic, with a naming convention applied to every constraint. Names matter here
because a constraint whose name is generated afresh looks like a drop plus an add
to Alembic, and dropping a unique index takes the guarantee away for the duration
of the rebuild.

`backend/alembic/versions/` is autogenerate output, so the formatter is kept away
from it — reformatting generated files produces churn that hides the real changes
on the next autogenerate run.

### 9.8 Not yet in place

Stated explicitly so nothing here is mistaken for a control that exists:

- **HTTPS is not yet enforced** by the application, and HSTS is not set. It is a
  deployment responsibility today.
- **No certificate pinning.** Deferred: it breaks certificate rotation in ways
  that lock a pilot out of its own API.
- **CORS defaults to empty**, which is correct for a mobile client and means
  browser origins are untrusted until deliberately configured.
- **No rate limiting** on sign-in. The decoy verification makes enumeration
  expensive per guess but does not bound the number of guesses.
- **No structured audit log** of access to academic records. Required before any
  institutional pilot.

---

## 10. Non-Functional Requirements

| Requirement            | Target / Approach                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------- |
| **Latency**            | Matching responses under 1–2 seconds under normal load                                         |
| **Availability**       | Stateless API allows horizontal scaling                                                        |
| **Bandwidth**          | Minimal payloads; images and heavy assets avoided where possible                               |
| **Offline resilience** | Client can queue non-critical actions; critical flows remain online-first                      |
| **Observability**      | Structured logging + future metrics (request latency, match success rate, rating distribution) |

---

## 11. Future Extension Points

- Institutional SSO and direct academic database integration
- LMS plugin / LTI support
- Advanced matching (topic embeddings, availability calendars)
- Analytics dashboard for university administrators
- Multi-university support with tenant isolation

---

## 12. Related Documents

- [Contribution Guide](./Contribution.md) — Contribution guidelines and Code of Conduct
- [Project Structure](./project-structure.md) — Repository layout and dependency direction
- [README.md](../README.md) — Project overview and local setup
- [MVP Brief](./MVP_Brief.md) - MVP Brief, covers what is in scope for the MVP and what is not and also future improvements.
- Pilot roadmap and research proposal (project root / docs)

---

**Maintainers**: Gilbert Asiimwe ([@asiimwe-dev](https://github.com/asiimwe-dev))

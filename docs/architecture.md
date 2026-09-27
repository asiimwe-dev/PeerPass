# Ulearn Architecture

**System Design & Technical Blueprint**

> This document describes the high-level architecture, core components, data model, matching engine, and validation protocol of Ulearn — a peer-to-peer academic support network for university students.

**Last Updated**: September 2026 | **Status**: Active

---

## 1. Vision & Design Goals

Ulearn exists to replace the “attend lectures and fight for your life” model with a reliable, stigma-free micro-intervention safety net. The architecture is shaped by the following goals:

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

- `auth` — Login, registration, SSO hand-off
- `profile` — Student / tutor profile & role management
- `matching` — Create topic requests, view matches, accept/reject
- `sessions` — Schedule, join, and complete micro-sessions
- `tutor_validation` — Upload transcript / link portfolio, view verification status
- `incentives` — View logged hours and certificate status

Shared layers:

- Network client (Dio or equivalent)
- Riverpod (or similar) for state management
- Core theme, constants, and reusable widgets

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
| **Users**         | `id`, `public_id`, `email`, `full_name`, `university_id`       | Identity. Roles live in `user_roles`, because one user may be both student and tutor   |
| **User_Roles**    | `user_id`, `role`                                              | Join table; composite primary key stops a role being held twice                         |
| **Tutor_Profiles**| `user_id`, `standing`, `rating_total`, `rating_count`, `certified_minutes` | Aggregate standing, stored rather than recomputed per matching query          |
| **Grading_Scales**| `max_points`, `competency_min_points`                          | The B+ bar as data, since pilot institutions disagree on what B+ means                 |
| **Grades**        | `label`, `grade_points`, `grading_scale_id`                    | Grade catalogue; one label per scale                                                    |
| **Course_Units**  | `code`, `name`, `university_id`, `subject_id`, `grade_id`      | Maps the exact university curriculum                                                    |
| **Competencies**  | `user_id`, `course_unit_id`, `grade_id`, `status`, `source`    | Validation gate requiring a verified grade at or above the scale's threshold            |
| **Refresh_Tokens**

- `id` (PK)
- `user_id` (FK → users)
- `token_hash` (unique) — the handle is a JWT; only its hash is stored, so a
  database disclosure does not yield usable refresh tokens
- `expires_at`, `revoked_at`
- `replaced_by_id` (FK → refresh_tokens, optional) — forms the chain that makes
  reuse of an already-rotated token detectable
- Every row is deleted on user deletion

**Help_Requests** | `tutee_id`, `course_unit_id`, `topic`, `status`                | What was asked for, before a tutor was matched                                          |
| **Sessions**      | `tutee_id`, `tutor_id`, `course_unit_id`, `status`, `duration_minutes` | A session that happened; the source for tutor hours and certificates          |
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

A peer-to-peer system is only useful if tutors are competent. Ulearn enforces quality through three sequential gates:

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

- **Authentication**: JWT for mobile sessions; designed for future University SSO (SAML/OAuth).
- **Authorization**: Role-based access control via `user_roles`, plus the
  competency and standing checks.
- **Data Protection**: Compliant with the Uganda Data Protection and Privacy Act, 2019 (DPPA). Sensitive academic data (grades, transcripts) requires explicit consent and secure storage.
- **Transport**: HTTPS only.
- **Secrets**: Never committed; loaded from environment variables.

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

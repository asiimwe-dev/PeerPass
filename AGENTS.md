# Ulearn contributor and agent guide

## Project context

Ulearn is a mobile-first peer tutoring network for university students. The
product connects tutees with verified peer tutors for focused academic
interventions, records completed sessions, and tracks tutor incentives.

Before changing behavior, read:

- `README.md` for product scope and local setup.
- `docs/Ulearn_Research_Document.md` for the problem, stakeholders, and pilot
  assumptions.
- `docs/architecture.md` for system boundaries, data model, matching, and
  validation rules.
- `docs/Contribution.md` for workflow, standards, and review requirements.

## Repository boundaries

- `frontend/` is the Flutter mobile client. Keep it feature-first and
  low-bandwidth friendly.
- `backend/` is the FastAPI service. Keep HTTP concerns in `app/api`, domain
  logic in `app/services`, persistence in `app/models`, and transport types in
  `app/schemas`.
- `backend/tests/` contains backend unit and integration tests.
- `frontend/test/` mirrors `frontend/lib/`, with `test/integration/` reserved
  for end-to-end runs of the real app.
- `docs/` contains architecture and project documentation.

The canonical client directory is `frontend/`. The `legacy/` directory is a
reference-only copy of an earlier layout attempt: it is not a buildable Flutter
project, it has no `pubspec.yaml`, and it is intentionally excluded from version
control. Do not add new code there, and do not treat it as a source of truth for
the current layout.

## Frontend architecture

`frontend/lib/` is feature-first with two layers per feature. A `domain/` layer is
deliberately absent: all matching, validation, grade, and rating rules are owned by
the backend, so a client-side domain layer would hold pass-through types with no
logic in it.

```text
lib/
├── main.dart            # ProviderScope and runApp only
├── app/                 # MaterialApp.router, GoRouter, auth redirect guard
├── core/                # shared foundations, no feature knowledge
└── features/<name>/     # data/ and presentation/
```

Within a feature, each directory has one job:

| Path                    | Role                                                     |
| ----------------------- | -------------------------------------------------------- |
| `data/models/`          | Wire DTOs for that feature's endpoints                   |
| `data/datasources/`     | Remote and in-memory fake data sources                   |
| `data/repositories/`    | The abstract contract, plus its implementation           |
| `presentation/`         | Screens, widgets, and Riverpod providers                 |

`core/models/` holds domain types genuinely shared by several features. Prefer a
new type in `core/models/` over a `shared/` directory, which has no enforceable
scope and becomes a dumping ground.

Dependency direction is strict:

- `core/` must never import from `features/`.
- `features/` may import from `core/`.
- A feature must not import another feature's `presentation/` layer. Cross-feature
  reuse goes through the owning feature's `data/repositories/` contract only.

## Domain invariants

- Tutor matching must consult validation and competency status before proposing
  a tutor.
- A tutor competency requires a verified B+ or higher unless an explicitly
  documented portfolio/manual override applies.
- Completed sessions require post-session ratings.
- Session records are the source for tutor hours and certificate eligibility.
- Academic records and credentials are sensitive: use environment variables for
  secrets, explicit consent for academic data, and HTTPS at runtime.

## Implementation standards

- Preserve the layered architecture; do not move business rules into Flutter
  widgets or route handlers.
- Use strong typing and narrow exception handling. Do not silently swallow
  validation, authorization, or persistence errors.
- Use snake_case for Python and Dart files, PascalCase for classes, camelCase
  for methods and variables, and UPPER_SNAKE_CASE for constants.
- Add focused tests for changed behavior, especially matching constraints,
  grade boundaries, rating thresholds, and session transitions.
- Update the relevant architecture or API documentation when a boundary or
  public behavior changes.

## Validation commands

Backend:

```bash
cd backend
pytest
```

The suite runs on in-memory SQLite by default and must stay runnable that way,
since CI has no database service for the fast job. It also runs against real
PostgreSQL, which is the only thing that actually proves the schema:

```bash
cd backend
ULEARN_TEST_DATABASE_URL=postgresql+psycopg://user:pass@localhost:5432/scratch_db pytest
```

That run drops and recreates the schema, so it must never be pointed at a
database holding real data. Any change to a model, a constraint, or a migration
needs both runs: SQLite will not catch a missing `numeric` scale or an
unconstrained enum column.

Frontend:

```bash
cd frontend
flutter analyze
flutter test
```

## Git workflow

Branch naming follows `docs/Contribution.md`:

| Type                | Use it for                            | Example                  |
| ------------------- | ------------------------------------- | ------------------------ |
| `feature/`, `fix/`  | New behavior and defect fixes         | `feature/tutor-matching` |
| `docs/`             | Documentation only                    | `docs/api-reference`     |
| `refactor/`         | Structural change, no new behavior    | `refactor/structure-setup` |
| `test/`             | Test additions or corrections         | `test/matching-constraints` |
| `chore/`            | Tooling and auxiliary configuration   | `chore/initialize-alembic` |

Commit messages use conventional commits, restricted to these types: `feat:`,
`fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:`.

```text
<type>: <subject>

<body>
```

The subject must start lowercase unless it begins with a proper noun, stay at or
below ~50 characters, use the imperative mood, and carry no trailing period. The
body explains the why. Keep one concern per commit and stay well under 1000
changed lines.

Rules that apply to every commit in this repository:

- Commit after each complete, verifiable step, so history reads as a sequence of
  working states rather than one large drop.
- Update the documentation a change invalidates in the same commit, as
  `docs/Contribution.md` requires for architecture changes.
- Never push. Leave publishing to the maintainer.
- Never add `Co-Authored-By`, `Signed-off-by`, or any other attribution trailer.
  Commits are authored solely by the repository owner using the identity already
  configured in git.
- Before committing, run the validation commands above and confirm `git status`
  contains only intended files.

# Contributing to Ulearn

**Professional Contribution Guidelines & Code of Conduct for the Ulearn Project**

> Complete guide for contributing code, reporting issues, and participating in the Ulearn community.  
> Learn our development workflow, code standards, review process, and behavioral expectations.

**Last Updated**: September 2026 | **Status**: Active | **Audience**: Contributors, Developers, Peer Tutors & Maintainers

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Our Standards](#our-standards)
3. [Enforcement](#enforcement)
4. [Getting Started](#getting-started)
5. [Before You Start](#before-you-start)
6. [Development Workflow](#development-workflow)
7. [Pull Request Process](#pull-request-process)
8. [Code Standards](#code-standards)
9. [Commit Message Guidelines](#commit-message-guidelines)
10. [Testing Requirements](#testing-requirements)
11. [Documentation Standards](#documentation-standards)
12. [Reporting Issues](#reporting-issues)
13. [Code Review Guidelines](#code-review-guidelines)
14. [Release & Versioning Policy](#release--versioning-policy)
15. [Common Mistakes](#common-mistakes)
16. [Getting Help](#getting-help)
17. [Recognition](#recognition)

---

## Code of Conduct

### Our Commitment

We, as contributors and maintainers of **Ulearn** (a Peer-to-Peer Academic Support Network), pledge to make participation in our community a harassment-free experience for everyone, regardless of age, body size, visible or invisible disability, ethnicity, sex characteristics, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.

We pledge to act and interact in ways that contribute to an open, welcoming, diverse, inclusive, and healthy community.

Ulearn is dedicated to providing a safe, respectful, and professional environment where:

- All contributors feel **safe and respected**
- Diverse perspectives are **valued and heard**
- Technical merit is the basis for all decisions
- Collaboration and continuous learning are encouraged

### Our Standards

Examples of behavior that contributes to a positive environment include:

- Demonstrating empathy and kindness toward other people
- Being respectful of differing opinions, viewpoints, and experiences
- Giving and gracefully accepting constructive feedback
- Accepting responsibility and apologizing to those affected by our mistakes, and learning from the experience
- Focusing on what is best not just for us as individuals, but for the overall community

Examples of unacceptable behavior include:

- The use of sexualized language or imagery, and sexual attention or advances of any kind
- Trolling, insulting or derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information, such as a physical or email address, without their explicit permission
- Other conduct which could reasonably be considered inappropriate in a professional setting

#### Expected Behavior (Quick Reference)

**DO:**

- Be Respectful — Treat all team members with courtesy and professionalism
- Be Collaborative — Share knowledge, help others, celebrate wins together
- Be Accountable — Take ownership of your code and its quality
- Be Professional — Focus on technical merit and constructive feedback
- Be Inclusive — Welcome contributions from people of all backgrounds and experience levels
- Be Curious — Learn from mistakes and improve continuously
- Ask Questions — Clarify requirements before implementing

**DON'T:**

- No Harassment — No bullying, discrimination, or personal attacks
- No Unwelcoming Behavior — No gatekeeping or exclusion based on experience
- No Unprofessionalism — No inappropriate language or behavior in public spaces
- No Plagiarism — Always credit sources and respect intellectual property
- No Conflicts of Interest — Disclose competing interests transparently
- No Shortcuts on Quality — Don't compromise testing or documentation
- No Disrespect to Reviewers — All feedback is meant to improve the code

### Enforcement Responsibilities

Project maintainers are responsible for clarifying and enforcing our standards of acceptable behavior and will take appropriate and fair corrective action in response to any behavior that they deem inappropriate, threatening, offensive, or harmful.

Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct, and will communicate reasons for moderation decisions when appropriate.

### Scope

This Code of Conduct applies within all project spaces, and also applies when an individual is officially representing the project in public spaces. Examples of representing our project include using an official e-mail address, posting via an official social media account, or acting as an appointed representative at an online or offline event.

### Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported to the project team at **gilbert.asiimwe.dev@gmail.com**. All complaints will be reviewed and investigated promptly and fairly.

All project maintainers are obligated to respect the privacy and security of the reporter of any incident.

### Enforcement Guidelines

Project maintainers will follow these Community Impact Guidelines in determining the consequences for any action they deem in violation of this Code of Conduct:

#### 1. Correction

**Community Impact**: Use of inappropriate language or other behavior deemed unprofessional or unwelcome in the community.  
**Consequence**: A private, written warning from project maintainers, providing clarity around the nature of the violation and an explanation of why the behavior was inappropriate. A public apology may be requested.

#### 2. Warning

**Community Impact**: A violation through a single incident or series of actions.  
**Consequence**: A warning with consequences for continued behavior. No interaction with the people involved, including unsolicited interaction with those enforcing the Code of Conduct, for a specified period of time. This includes avoiding interactions in community spaces as well as external channels like social media. Violating these terms may lead to a temporary or permanent ban.

#### 3. Temporary Ban

**Community Impact**: A serious violation of community standards, including sustained harassing behavior.  
**Consequence**: A temporary ban from any sort of interaction or public communication with the community for a specified period of time. No public or private interaction with the people involved, including unsolicited interaction with those enforcing the Code of Conduct, is allowed during this period. Violating these terms may lead to a permanent ban.

#### 4. Permanent Ban

**Community Impact**: Demonstrating a pattern of violation of community standards, including sustained harassing behavior, harassment of an individual, or aggression toward or disparagement of classes of individuals.  
**Consequence**: A permanent ban from any sort of public interaction within the community.

**Report Violations**: Contact project maintainers privately via:

- GitHub: [@asiimwe-dev](https://github.com/asiimwe-dev)
- Email: gilbert.asiimwe.dev@gmail.com

All reports are **confidential** and investigated promptly.

---

## Getting Started

### Step 1: Fork and Clone

```bash
# 1. Fork the repository on GitHub
# (Click "Fork" on the Ulearn repository)

# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/Ulearn.git
cd Ulearn

# 3. Add upstream remote
git remote add upstream https://github.com/asiimwe-dev/Ulearn.git
```

### Step 2: Create Feature Branch

```bash
# Always create a new branch from the latest main (or develop)
git fetch upstream
git checkout -b feature/your-feature-name upstream/main

# Branch naming convention:
# feature/description   — New feature
# fix/description       — Bug fix
# docs/description      — Documentation only
# refactor/description  — Code refactoring
# test/description      — Test additions or improvements
```

### Step 3: Set Up Development Environment

#### Backend (FastAPI + PostgreSQL)

```bash
# Navigate to backend directory
cd backend

# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate          # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start PostgreSQL (example with Podman/Docker)
podman run --name p2p-postgres \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=Ulearn \
  -p 5432:5432 -d postgres:latest

# Apply migrations and start the server
alembic upgrade head
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> API documentation will be available at `http://localhost:8000/docs`

#### Frontend (Flutter)

```bash
# Navigate to frontend directory
cd frontend

# Install dependencies
flutter pub get

# Verify setup
flutter doctor
flutter analyze   # Should show 0 issues
flutter test      # All tests should pass

# Run the app
flutter run
```

---

## Before You Start

### Check These First

1. **Browse Existing Issues**  
   Visit the project's GitHub Issues. Is your feature or bug already being worked on? Are there related discussions?

2. **Review the Project Vision**  
   Read the project README and research/proposal documents. Align your work with Ulearn's goals of reducing retake rates through verified peer tutoring.

3. **Understand the Architecture**  
   Read **[Architecture](./architecture.md)**  
   Familiarize yourself with the modular design, matching engine, multi-tier validation protocol, and data model before contributing:
   - Flutter frontend (mobile-first, low-bandwidth optimized)
   - FastAPI backend (RESTful matching & routing logic)
   - PostgreSQL (users, course units, competencies, session logs)
   - Review the [Project Structure](./project-structure.md) for repository layout and dependency direction.

4. **Discuss Major Changes**  
   For significant features or architectural changes, open an issue first and get feedback before implementing. This prevents wasted effort.

---

## Development Workflow

### Step 1: Make Changes

- Keep changes focused on one concern
- Follow the code standards below
- Write clear, maintainable code with proper documentation

### Step 2: Test Locally

**Backend**

```bash
pytest
# or specific tests
pytest tests/test_matching.py
```

**Frontend**

```bash
flutter analyze
flutter test
flutter test test/modules/matching/   # module-specific
flutter run                           # on emulator/device
```

### Step 3: Commit Changes

```bash
git add .
git commit -m "feat: Add competency verification endpoint

- Validates minimum B+ grade for tutor eligibility
- Integrates with Course_Units and Competencies tables
- Adds unit tests for boundary grades"
git push origin feature/your-feature-name
```

### Step 4: Create Pull Request

- Open a PR from your branch to the upstream `main` (or `develop`) branch
- Fill out the PR template completely
- Link related issues
- Request reviewers

---

## Pull Request Process

### PR Requirements

Every PR must include:

1. **Clear Title** — Starts with a conventional commit prefix
   - `feat: Add session rating feedback loop`
   - `fix: Resolve matching algorithm race condition`
   - `docs: Update tutor validation documentation`
   - `refactor: Simplify competency gate logic`

2. **Detailed Description** — What, Why, How

   ```markdown
   ## What

   Added multi-tier tutor validation (academic grade + portfolio + probationary ratings)

   ## Why

   Ensures academic integrity of the peer tutoring network

   ## How

   - Integrated transcript grade check (minimum B+)
   - Added optional GitHub/portfolio verification
   - Implemented provisional → verified status transition based on ratings

   ## Related Issues

   Fixes #42
   ```

3. **Tests**
   - New features: ≥ 80% coverage of changed code
   - Bug fixes: Include a test that reproduces the bug
   - Refactoring: No coverage loss

4. **Documentation**
   - User-facing changes → update README
   - API changes → update code comments / OpenAPI docs
   - Architecture changes → update relevant design docs

5. **No Conflicts** — Keep your branch up to date
   ```bash
   git fetch upstream
   git rebase upstream/main
   git push -f origin feature/your-feature-name
   ```

### PR Review Checklist

Reviewers look for:

- Correctness — Does it work? Are edge cases handled?
- Design — Does it follow the modular architecture?
- Tests — Are critical paths covered?
- Performance — Any obvious inefficiencies (especially matching latency)?
- Maintainability — Is the code easy to understand?
- Documentation — Is the change explained?

### Merging

- All tests pass
- All feedback addressed
- Approved by at least one maintainer
- No merge conflicts
- Prefer squash-and-merge for clean history

---

## Code Standards

### File Organization (Dart / Flutter)

```dart
// 1. Imports (grouped and alphabetically ordered)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 2. Constants
const int MAX_TOPIC_LENGTH = 120;

// 3. Main class / widget
class MatchingRequestCard extends ConsumerWidget {
  // ...
}

// 4. Private helpers
class _RatingBadge {
  // ...
}
```

### Naming Conventions

| Element        | Convention       | Example                           |
| -------------- | ---------------- | --------------------------------- |
| Classes        | PascalCase       | `TutorProfile`, `SessionLog`      |
| Methods        | camelCase        | `matchTutor()`, `validateGrade()` |
| Variables      | camelCase        | `unitCode`, `averageRating`       |
| Constants      | UPPER_SNAKE_CASE | `MIN_GRADE`, `DEFAULT_TIMEOUT`    |
| Private        | Leading `_`      | `_internalState`, `_validate()`   |
| Files          | snake_case       | `tutor_profile.dart`              |
| Python modules | snake_case       | `matching_engine.py`              |

### Code Style Highlights

- Prefer strong typing; avoid `dynamic` / untyped variables
- Use specific exception handling rather than bare `except`
- Prefer `const` constructors in Flutter where possible
- Document public APIs with clear doc comments that explain **why**, not just what
- Keep functions focused and reasonably short

### Comments

```dart
/// Validates that a student has achieved at least a B+ in the target course unit.
///
/// This is the hard gate of the multi-tier tutor validation protocol.
/// Students who do not meet the grade threshold cannot register as tutors
/// for that unit.
bool hasMinimumGrade(String unitId, String grade) {
  // ...
}
```

---

## Commit Message Guidelines

### Format

```
<type>: <subject>

<body>

<footer>
```

### Types

- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `style:` — Formatting, whitespace, etc.
- `refactor:` — Code change that neither fixes a bug nor adds a feature
- `perf:` — Performance improvement
- `test:` — Adding or correcting tests
- `chore:` — Build process or auxiliary tool changes

### Subject

- Start with lowercase (unless proper noun)
- Maximum ~50 characters
- Imperative mood (“add” not “added” or “adds”)
- No trailing period

### Example

```
feat: implement provisional tutor rating gate

Newly verified tutors start with a Provisional badge. After a
configurable number of sessions with average rating above the
threshold they are promoted to Verified Tutor status.

Ratings below the threshold automatically reduce matching priority.

Fixes #57
```

---

## Testing Requirements

### Coverage Targets

- New features: ≥ 80% coverage of the changed code
- Bug fixes: Must include a reproducing test case
- Refactoring: No reduction in existing coverage

### Writing Good Tests

- Use clear, descriptive test names that state the expected behavior
- Cover edge cases and boundary values (especially grade thresholds, rating cut-offs, and matching constraints)
- Mock external dependencies (university SSO, GitHub API, etc.)
- Prefer focused unit tests for domain logic; integration tests for the matching engine and session flow

### Running Tests

```bash
# Backend, on in-memory SQLite
pytest
pytest --cov=app

# The same suite against real PostgreSQL. Worth running before any change to a
# model, a constraint, or a migration. SQLite does not enforce numeric precision,
# does not apply the constraint naming convention, and treats an enum column as
# an unconstrained VARCHAR, so a green SQLite run is not evidence the schema is
# valid where it will run. CI runs both.
cd backend
ULEARN_TEST_DATABASE_URL=postgresql+psycopg://ulearn:ulearn@localhost:5432/ulearn_test pytest

# Frontend
flutter test
flutter test --coverage
flutter test --name="matching"
```

The PostgreSQL run drops and recreates the schema in the target database, so point
it at a scratch database. It must never be given a URL holding real data.

---

## Documentation Standards

- Use clear hierarchical headings
- Include a table of contents for longer documents
- Provide concrete code examples for non-obvious behavior
- Link related files with relative Markdown links
- Keep lines reasonably short for readability
- Document public APIs thoroughly (parameters, return values, exceptions, side effects)

---

## Reporting Issues

### Bug Report Template

```markdown
## Description

Brief, clear description of the bug.

## Steps to Reproduce

1. ...
2. ...
3. Expected result vs actual result

## Environment

- Flutter version: ...
- Python / FastAPI version: ...
- OS: ...
- Device / Emulator: ...

## Logs / Stack Trace
```

### Feature Requests

Open an issue describing the problem you want to solve, the proposed solution, and any alternatives you considered. Align requests with Ulearn’s core mission of verified, low-friction peer academic support.

---

## Code Review Guidelines

### For Authors

- Keep PRs small and focused (< ~400 lines of change where practical)
- Provide context and explain the “why”
- Respond to all feedback
- Request re-review after addressing comments

### For Reviewers

- Aim to review within 24–48 hours
- Be respectful and constructive
- Offer specific, actionable suggestions
- Acknowledge good work

---

## Release & Versioning Policy

Ulearn follows Semantic Versioning (`MAJOR.MINOR.PATCH`):

- **MAJOR** — Incompatible API or architectural changes
- **MINOR** — New features in a backward-compatible manner
- **PATCH** — Backward-compatible bug fixes

### Branching Strategy

- `main` — Production-ready code
- `develop` — Integration branch (if used)
- `feature/*` — Individual features
- `hotfix/*` — Emergency fixes targeting `main`

---

## Common Mistakes

| Mistake                              | Preferred Approach                          |
| ------------------------------------ | ------------------------------------------- |
| Committing directly to `main`        | Always work on a feature branch             |
| Mixing multiple concerns in one PR   | Keep PRs focused on a single change         |
| Missing tests for new logic          | Add tests before (or with) the PR           |
| Ignoring `flutter analyze` / linters | Run analysis before committing              |
| Very large PRs (1000+ LOC)           | Split into smaller, reviewable PRs          |
| Vague commit messages                | Use conventional commits with clear subject |
| Leaving merge conflicts unresolved   | Rebase regularly on the target branch       |

---

## Getting Help

- **Issues**: Project GitHub Issues
- **Discussions**: Project GitHub Discussions (if enabled)
- **Documentation**:
  - [Architecture](./architecture.md) — System design, data model, matching engine & validation
  - [Project Structure](./project-structure.md) — Repository layout and dependency direction
  - [README](../README.md) — Project overview and local setup
  - [MVP Brief](./MVP_Brief.md) - Covers what is in scope and what is to be integrated beyond the MVP.
- **Direct contact**: gilbert.asiimwe.dev@gmail.com or [@asiimwe-dev](https://github.com/asiimwe-dev)

Before opening a new issue, search existing issues and discussions.

---

## Recognition

We celebrate all contributions. Contributors are recognized in:

- The GitHub contributor graph
- Release notes
- The project README

---

**Thank you for contributing to Ulearn!**  
Your work helps create a stigma-free academic safety net for university students and strengthens peer-supported learning across institutions.

---

**Attribution**

The Code of Conduct section is adapted from the [Contributor Covenant](https://www.contributor-covenant.org), version 2.0.  
Community Impact Guidelines were inspired by [Mozilla’s code of conduct enforcement ladder](https://github.com/mozilla/diversity).

<<<<<<< HEAD
# Ulearn
=======
# PeerPass
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121

**A Peer-to-Peer Academic Support Network**

> Dismantling the "attend lectures and fight for your life" model.  
<<<<<<< HEAD
> Ulearn matches struggling university students with verified peer tutors for focused, stigma-free micro-interventions — reducing retake rates and academic drop-off.
=======
> PeerPass matches struggling university students with verified peer tutors for focused, stigma-free micro-interventions — reducing retake rates and academic drop-off.
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121

[![Flutter](https://img.shields.io/badge/Frontend-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-336791?logo=postgresql)](https://www.postgresql.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

---

## Overview

<<<<<<< HEAD
Ulearn is a localized, dynamic platform designed for Ugandan (and East African) universities. It connects students who need help on hyper-specific topics with peer tutors who have proven competency in those exact areas.
=======
PeerPass is a localized, dynamic platform designed for Ugandan (and East African) universities. It connects students who need help on hyper-specific topics with peer tutors who have proven competency in those exact areas.
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121

The platform operates on a **B2B / incentive-based model** backed by institutions or corporate sponsors. Students receive frictionless academic support; tutors earn verified Teaching Assistant certificates and leadership credits.

---

## Core Features

| Feature                            | Description                                                                                                                                                                      |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Targeted Matching Engine**       | Connects a student's specific topic request (e.g. _"Matrix Transformations"_ or _"Database Normalization"_) with a peer tutor who has verified competency in that exact area.    |
| **Multi-Tiered Validation Engine** | Ensures academic integrity through: (1) transcript grade verification (minimum B+ / A), (2) optional external portfolio proof, and (3) mandatory post-session community ratings. |
| **Incentivization Tracking**       | Automatically logs tutoring hours and generates verified Teaching Assistant certificates + leadership credits for peer tutors.                                                   |
| **Frictionless Scheduling**        | In-app coordination optimized for mobile-first, low-bandwidth environments.                                                                                                      |

---

## System Architecture

<<<<<<< HEAD
Ulearn is built as a modular, high-performance system designed for eventual integration with institutional Learning Management Systems (LMS).
=======
PeerPass is built as a modular, high-performance system designed for eventual integration with institutional Learning Management Systems (LMS).
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121

| Layer        | Technology       | Purpose                                                                    |
| ------------ | ---------------- | -------------------------------------------------------------------------- |
| **Frontend** | Flutter          | Cross-platform mobile app optimized for low-bandwidth use                  |
| **Backend**  | FastAPI (Python) | Low-latency RESTful API for routing, matching logic & session management   |
| **Database** | PostgreSQL       | Relational storage for users, course units, competencies, and session logs |

For a full technical deep-dive (data model, matching engine, validation protocol, and design decisions), see:

**[Architecture Documentation](./docs/architecture.md)**

---

## Prerequisites

Ensure the following tools are installed on your local development environment:

- [Flutter SDK](https://docs.flutter.dev/install/manual) (latest stable)
- [Python 3.10+](https://www.python.org/downloads/)
- [PostgreSQL](https://www.postgresql.org/download/) (or use the container method below)
- [Git](https://github.com/git-guides/install-git)

---

## Local Development Setup

### 1. Database (Podman or Docker)

```bash
podman run --name p2p-postgres \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD=secret \
<<<<<<< HEAD
  -e POSTGRES_DB=Ulearn \
=======
  -e POSTGRES_DB=PeerPass \
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121
  -p 5432:5432 \
  -d postgres:latest
```

### 2. Backend (FastAPI)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Apply migrations and start the server
alembic upgrade head
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> API documentation is available at [http://localhost:8000/docs](http://localhost:8000/docs)

### 3. Frontend (Flutter)

```bash
cd frontend
flutter pub get
flutter run
```

---

## Regulatory Compliance

<<<<<<< HEAD
Ulearn is engineered for institutional deployment and adheres to:
=======
PeerPass is engineered for institutional deployment and adheres to:
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121

- **Uganda Data Protection and Privacy Act, 2019 (DPPA)** — Explicit consent, secure storage, and registration requirements for handling sensitive academic data (transcripts & grades)
- **Electronic Transactions Act, 2011** — Intermediary liability protections
- **Institutional IT Policies** — Network security compliance when querying student portals or integrating SSO

---

## Pilot Implementation Roadmap

The project is structured for a focused deployment cycle:

1. **Phase 1 – Pre-Pilot**  
   Legal & institutional alignment, faculty buy-in, and initial tutor vetting (10–20 tutors)

2. **Phase 2 – Closed Beta ("Sandbox")**  
   Launch to a single high-failure-rate course unit (e.g. Computer Science – Database Programming)

3. **Phase 3 – Controlled Rollout**  
   Expand to 3–5 courses across different faculties

4. **Phase 4 – Post-Pilot Evaluation**  
   Aggregate session logs, tutor ratings, and impact on continuous assessment scores for official adoption discussions

---

## Documentation

| Document                                   | Description                                                              |
| ------------------------------------------ | ------------------------------------------------------------------------ |
| **[Architecture](./docs/architecture.md)** | System design, data model, matching engine & validation protocol         |
| **[Contributing](./docs/Contribution.md)** | Code of Conduct, development workflow, coding standards & review process |

---

## Contributing

We welcome contributions of all kinds — code, documentation, testing, and ideas.

<<<<<<< HEAD
Please read **[CONTRIBUTING.md](./docs/Contribution.md)** before submitting any pull request.  
=======
Please read **[Contribution Guide](./docs/Contribution.md)** before submitting any pull request.  
>>>>>>> 48c4f527679b8c55f4e3a015c45d6ff56ce12121
It contains our full Code of Conduct, development workflow, coding standards, and review process.

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](./LICENSE) file for details.

---

## Inquiries & Collaboration

- **Maintainer**: [Gilbert Asiimwe](https://github.com/asiimwe-dev)
- **Email**: [gilbert.asiimwe.dev@gmail.com](mailto:gilbert.asiimwe.dev@gmail.com)

For critical issues or partnership discussions, please reach out directly.

---

**Built to help students stop struggling in silence.**

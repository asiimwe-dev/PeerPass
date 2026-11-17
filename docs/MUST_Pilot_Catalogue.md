# MUST FCI undergraduate catalogue

## Pilot scope

The pilot catalogue is limited to MUST's **Faculty of Computing and
Informatics**. Postgraduate programmes and every other faculty are excluded
until a later scope decision.

The seed currently publishes these undergraduate degrees:

- Computer Science
- Information Technology
- Software Engineering

The course-unit list is sourced from PR #39. It contains 62 FCI units using the
codes and names supplied there, with the PR's faculty label normalized to the
pilot label **Faculty of Computing and Informatics**. The PR includes Software
Engineering units even though its programme list omitted the degree; the seed
therefore includes Software Engineering explicitly. `DCS1101` is omitted: it
belongs to no seeded programme, so it would have been a unit no student could
declare or ask about.

Each unit is published by exactly one programme, and its code prefix names that
programme: `BIT` → Information Technology, `CSC` → Computer Science, `SWE` →
Software Engineering. That mapping is seed data, not a request-time inference; the
database stores `course_units.program_id`. The schema also supports a faculty-wide
unit (`program_id` null), visible to every programme in the faculty, though the
shipped catalogue is entirely programme-owned.

## Data ownership

PR #39 is an engineering source for the pilot catalogue, not a substitute for
MUST approval. Before invitations are issued, FCI must confirm:

1. The three undergraduate degree names.
2. The 62 course-unit codes and names that are launchable, and the programme each
   belongs to.
3. The initial tutor cohort and the units each tutor may support.

The seed is idempotent and can be rerun with:

```bash
cd backend
python -m app.db.seed
```

The course-unit endpoint is faculty-scoped, and narrowed again to the caller's
programme. A student with no faculty or with a faculty whose catalogue is empty
receives an empty list and can still complete onboarding; a student with no
programme sees the whole faculty, which is the compatibility state.

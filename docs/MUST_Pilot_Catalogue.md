# MUST pilot catalogue

## Status

This is the **provisional engineering catalogue** for the closed MUST pilot.
It is not a complete MUST curriculum and does not represent institutional
approval. The pilot must not advertise a unit as available until MUST confirms
the launch list and participating tutor cohort.

The seed currently exposes only the six existing course-unit records below.
They are the initial technical candidates because they have real unit codes and
names in the repository. Programme names are not converted into course units:
a programme such as Computer Science is a degree programme, while a course unit
such as BIT 221 is a matchable learning unit.

## Provisional launch candidates

| Faculty | Code | Course unit |
| --- | --- | --- |
| Faculty of Computing and Informatics Sciences | BIT 221 | Operating Systems |
| Faculty of Computing and Informatics Sciences | BIT 223 | Database Programming |
| Faculty of Computing and Informatics Sciences | BIT 225 | Computer Networks |
| Faculty of Science | SCH 211 | Organic Chemistry |
| Faculty of Science | PHY 212 | Thermodynamics |
| Faculty of Science | MTH 213 | Linear Algebra |

## Approval and change process

Before pilot invitations are issued, MUST operations must provide:

1. The exact course-unit list to make available.
2. The academic owner or source for each listed unit.
3. The initial tutor cohort and the units each tutor may support.

Engineering may update the seed with confirmed units, but must not invent unit
codes or infer them from faculty/programme descriptions. Any unconfirmed row
must remain clearly provisional or be removed from the launch seed.

The source of this data is `backend/app/db/seed.py`; running
`python -m app.db.seed` is idempotent and does not remove existing rows.

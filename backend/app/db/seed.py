"""Reference data for the pilot institution.

Run it with `python -m app.db.seed`. Idempotent, so it is safe to re-run after a
migration.

The pilot is a single institution, so the seed holds a single university. It is
not filler: the onboarding wizard's pickers read these rows, and an empty
catalogue would leave those screens with nothing to show.

This is not a migration. Migrations move a schema between versions and are
written by hand; this fills tables whose contents are reference data, using the
tables the migrations already created.
"""

import asyncio
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session_factory
from app.models.course_unit import CourseUnit, Subject, University
from app.models.grading_scale import Grade, GradingScale

UNIVERSITY_NAME = "Mbarara University of Science and Technology"

#: MUST's undergraduate scale is a five-point scale, not a percentage one, and
#: the difference is load-bearing. A tutor's standing is stored as points, so a
#: percentage figure would put the number in the wrong unit twice over: in the
#: column, and in the comparison the matching engine makes.
SCALE_NAME = "MUST Undergraduate (5-point)"

#: The published maximum. `grades.max_points` is denormalised from this, which is
#: why a scale's maximum is treated as write-once once seeded.
MAX_POINTS = Decimal("5.00")

#: B+ is worth 4 points and is the bar a tutor must clear.
#:
#: Stored as data rather than as a constant in the matching code because the bar
#: belongs to the institution, not to the product. The next university added will
#: have its own, and changing one must not change another's.
#:
#: On MUST's published bands this is 65%, so B+ and everything above it
#: qualifies and B, at 55-64%, does not.
COMPETENCY_MIN_POINTS = Decimal("4.00")

#: A through D, best first.
#:
#: F is deliberately absent. `grades` carries a `grade_points > 0` check and F is
#: worth zero, so it cannot be represented on this scale without relaxing a
#: constraint the schema relies on. It is also not needed: a student's result is
#: a `Competency`, which asserts competence, and nobody claims competence with a
#: fail. Representing F belongs with transcript display, if that is ever built.
GRADES: tuple[tuple[str, str], ...] = (
    ("A", "5.00"),
    ("B+", "4.00"),
    ("B", "3.00"),
    ("C", "2.00"),
    ("D", "1.00"),
)

FACULTIES: tuple[str, ...] = (
    "Faculty of Applied Sciences and Technology",
    "Faculty of Biological Sciences",
    "Faculty of Business Administration and Management",
    "Faculty of Computing and ICT",
    "Faculty of Education",
    "Faculty of Engineering",
    "Faculty of Medicine",
    "Faculty of Social Sciences",
    "Faculty of Science",
)

#: A starting catalogue: `(faculty, code, name)`.
#:
#: Real unit codes rather than placeholders, because a screen that renders
#: `BIT 221 Operating Systems` is being tested and one that renders `FAC-1
#: Course 1` is not. A handful per faculty is enough to prove the grouping works;
#: the full catalogue is an administrator's job.
COURSE_UNITS: tuple[tuple[str, str, str], ...] = (
    ("Faculty of Computing and ICT", "BIT 221", "Operating Systems"),
    ("Faculty of Computing and ICT", "BIT 223", "Database Programming"),
    ("Faculty of Computing and ICT", "BIT 225", "Computer Networks"),
    ("Faculty of Science", "SCH 211", "Organic Chemistry"),
    ("Faculty of Science", "PHY 212", "Thermodynamics"),
    ("Faculty of Science", "MTH 213", "Linear Algebra"),
    (
        "Faculty of Business Administration and Management",
        "ACC 211",
        "Financial Accounting",
    ),
    (
        "Faculty of Business Administration and Management",
        "MKT 214",
        "Marketing Research",
    ),
    ("Faculty of Engineering", "ENG 221", "Thermodynamics II"),
    ("Faculty of Engineering", "CIV 222", "Structural Analysis"),
)


async def _seed_grading_scale(db: AsyncSession) -> GradingScale:
    """MUST's scale and its grade catalogue, created if absent."""
    scale = await db.scalar(select(GradingScale).where(GradingScale.name == SCALE_NAME))
    if scale is None:
        scale = GradingScale(
            name=SCALE_NAME,
            max_points=MAX_POINTS,
            competency_min_points=COMPETENCY_MIN_POINTS,
        )
        db.add(scale)
        await db.flush()

    present = set(
        (
            await db.execute(
                select(Grade.label).where(Grade.grading_scale_id == scale.id)
            )
        ).scalars()
    )
    for label, points in GRADES:
        if label not in present:
            db.add(
                Grade(
                    label=label,
                    grade_points=Decimal(points),
                    max_points=MAX_POINTS,
                    grading_scale_id=scale.id,
                )
            )
    await db.flush()
    return scale


async def _seed_subjects(db: AsyncSession) -> dict[str, Subject]:
    """The faculties, keyed by name, with any missing ones added."""
    subjects = {row.name: row for row in (await db.execute(select(Subject))).scalars()}
    for name in FACULTIES:
        if name not in subjects:
            subject = Subject(name=name)
            db.add(subject)
            subjects[name] = subject
    await db.flush()
    return subjects


async def _seed_university(db: AsyncSession, scale: GradingScale) -> University:
    """MUST, attached to the scale its grades are awarded on."""
    university = await db.scalar(
        select(University).where(University.name == UNIVERSITY_NAME)
    )
    if university is None:
        university = University(name=UNIVERSITY_NAME, grading_scale_id=scale.id)
        db.add(university)
        await db.flush()
    return university


async def _seed_course_units(
    db: AsyncSession, university: University, subjects: dict[str, Subject]
) -> tuple[int, list[str]]:
    """The starting catalogue. Returns the count added and any unmatched faculties."""
    present = set(
        (
            await db.execute(
                select(CourseUnit.code).where(CourseUnit.university_id == university.id)
            )
        ).scalars()
    )

    added = 0
    orphans: set[str] = set()
    for faculty, code, name in COURSE_UNITS:
        if code in present:
            continue
        subject = subjects.get(faculty)
        if subject is None:
            orphans.add(faculty)
        db.add(
            CourseUnit(
                code=code,
                name=name,
                university_id=university.id,
                subject_id=subject.id if subject is not None else None,
                # `grade_id` is left null deliberately. A unit awards a range of
                # grades, not one, and the grade a student actually got is named
                # by their `Competency`. Assigning a single grade to every unit
                # would invent data that the model already has a correct place
                # for. The unit's scale is inherited from its university either
                # way, which is what the matching engine reads.
                grade_id=None,
            )
        )
        added += 1
    await db.flush()
    return added, sorted(orphans)


async def seed(db: AsyncSession) -> None:
    """Fill in the pilot's reference data and report what it did."""
    scale = await _seed_grading_scale(db)
    subjects = await _seed_subjects(db)
    university = await _seed_university(db, scale)
    added, orphans = await _seed_course_units(db, university, subjects)
    await db.commit()

    print(f"Seeded {UNIVERSITY_NAME}")
    print(
        f"  grading scale : {SCALE_NAME} "
        f"(max {MAX_POINTS}, gate {COMPETENCY_MIN_POINTS})"
    )
    print(f"  grades        : {', '.join(label for label, _ in GRADES)}")
    print(f"  faculties     : {len(subjects)}")
    print(f"  course units  : {added} added")
    if orphans:
        # Loud rather than silent: a unit with no faculty is invisible in the
        # wizard's faculty filter, which looks like a bug from the student's
        # side and has no other symptom.
        print(f"  WARNING: no faculty row for {', '.join(orphans)}")


def main() -> None:
    """Entry point for `python -m app.db.seed`."""

    async def _run() -> None:
        async with get_session_factory()() as session:
            await seed(session)

    asyncio.run(_run())


if __name__ == "__main__":
    main()

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
from app.core.pilot import PILOT_UNIVERSITY_NAME
from app.models.course_unit import CourseUnit, Program, Subject, University
from app.models.course_unit_topic import CourseUnitTopic
from app.models.grading_scale import Grade, GradingScale

UNIVERSITY_NAME = PILOT_UNIVERSITY_NAME

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
COMPETENCY_MIN_POINTS = Decimal("4.50")

#: A through D, best first.
#:
#: F is deliberately absent. `grades` carries a `grade_points > 0` check and F is
#: worth zero, so it cannot be represented on this scale without relaxing a
#: constraint the schema relies on. It is also not needed: a student's result is
#: a `Competency`, which asserts competence, and nobody claims competence with a
#: fail. Representing F belongs with transcript display, if that is ever built.
GRADES: tuple[tuple[str, str], ...] = (
    ("A", "5.00"),
    ("B+", "4.50"),
    ("B", "4.00"),
    ("C+", "3.50"),
    ("C", "3.00"),
    ("D+", "2.50"),
    ("D", "2.00"),
)

FACULTIES: tuple[tuple[str, str], ...] = (
    (
        "Faculty of Computing and Informatics",
        "Drives technology education through computing, information technology, "
        "and software engineering undergraduate programs.",
    ),
)

PROGRAMS: tuple[tuple[str, str, str], ...] = (
    ("Faculty of Computing and Informatics", "undergraduate", "Computer Science"),
    (
        "Faculty of Computing and Informatics",
        "undergraduate",
        "Information Technology",
    ),
    (
        "Faculty of Computing and Informatics",
        "undergraduate",
        "Software Engineering",
    ),
)

#: FCI undergraduate catalogue from PR #39: `(faculty, code, name)`.
#:
#: The pilot intentionally excludes postgraduate degrees and non-FCI faculties.
#: Course units remain faculty-scoped in the current schema; the degree list is
#: the authoritative undergraduate offering shown during onboarding.
COURSE_UNITS: tuple[tuple[str, str, str], ...] = (
    ("Faculty of Computing and Informatics", "BIT1101", "Fundamentals of ICT"),
    ("Faculty of Computing and Informatics", "BIT1103", "Principles of Programming: C"),
    (
        "Faculty of Computing and Informatics",
        "BIT1104",
        "Fundamentals of Information Systems",
    ),
    (
        "Faculty of Computing and Informatics",
        "BIT1105",
        "Mathematics for Information Technology",
    ),
    (
        "Faculty of Computing and Informatics",
        "BIT1106",
        "Principals of Programming: Python",
    ),
    ("Faculty of Computing and Informatics", "BIT1206", "Advanced Python Programming"),
    (
        "Faculty of Computing and Informatics",
        "BIT2101",
        "Object Oriented Programming 2",
    ),
    ("Faculty of Computing and Informatics", "BIT2102", "Systems Security"),
    ("Faculty of Computing and Informatics", "BIT2103", "Database Management Systems"),
    ("Faculty of Computing and Informatics", "BIT2104", "Computer Networking"),
    (
        "Faculty of Computing and Informatics",
        "BIT2105",
        "Financial Management for IT professionals",
    ),
    ("Faculty of Computing and Informatics", "BIT2106", "Agile Project Management"),
    ("Faculty of Computing and Informatics", "BIT2107", "Software Engineering"),
    ("Faculty of Computing and Informatics", "BIT3101", "Human Computer Interaction"),
    (
        "Faculty of Computing and Informatics",
        "BIT3103",
        "Geographic Information Systems",
    ),
    ("Faculty of Computing and Informatics", "BIT3104", "Artificial Intelligence"),
    (
        "Faculty of Computing and Informatics",
        "BIT3105",
        "Mobile computing and Data communications",
    ),
    (
        "Faculty of Computing and Informatics",
        "BIT3106",
        "Innovations and Entrepreneurship in IT",
    ),
    ("Faculty of Computing and Informatics", "BIT3107", "Sensor Technologies"),
    (
        "Faculty of Computing and Informatics",
        "BIT3108",
        "Organizational Management for IT professionals",
    ),
    ("Faculty of Computing and Informatics", "CSC1101", "Computer Skills"),
    ("Faculty of Computing and Informatics", "CSC1102", "Principles of Programming"),
    (
        "Faculty of Computing and Informatics",
        "CSC1103",
        "Computer Organisation and Architecture",
    ),
    (
        "Faculty of Computing and Informatics",
        "CSC1104",
        "Communication and Writing Skills for Computer Scientists",
    ),
    ("Faculty of Computing and Informatics", "CSC1114", "Communication Skills"),
    ("Faculty of Computing and Informatics", "CSC1121", "Computer Skills"),
    ("Faculty of Computing and Informatics", "CSC2101", "Operating Systems"),
    (
        "Faculty of Computing and Informatics",
        "CSC2102",
        "Object Oriented Programming- Java II",
    ),
    ("Faculty of Computing and Informatics", "CSC2104", "Database programming"),
    ("Faculty of Computing and Informatics", "CSC2105", "Systems Analysis and Design"),
    ("Faculty of Computing and Informatics", "CSC2106", "Scientific Thinking"),
    ("Faculty of Computing and Informatics", "CSC3101", "Software Project Management"),
    ("Faculty of Computing and Informatics", "CSC3102", "Artificial Intelligence"),
    ("Faculty of Computing and Informatics", "CSC3103", "Embedded Systems"),
    ("Faculty of Computing and Informatics", "CSC3104", "Computational Complexity"),
    ("Faculty of Computing and Informatics", "CSC3105", "Multimedia Technology"),
    (
        "Faculty of Computing and Informatics",
        "CSC3106",
        "Wireless and Mobile Communications",
    ),
    (
        "Faculty of Computing and Informatics",
        "CSC3109",
        "Mobile Applications Development",
    ),
    (
        "Faculty of Computing and Informatics",
        "CSC3111",
        "Computer Vision & Image Processing",
    ),
    ("Faculty of Computing and Informatics", "DCS1101", "Computer Skils"),
    ("Faculty of Computing and Informatics", "SWE1101", "DISCRETE MATHEMATICS"),
    ("Faculty of Computing and Informatics", "SWE1103", "Linear Algebra"),
    (
        "Faculty of Computing and Informatics",
        "SWE1104",
        "Software Development Principles",
    ),
    ("Faculty of Computing and Informatics", "SWE1105", "COMMUNICATION SKILLS"),
    ("Faculty of Computing and Informatics", "SWE2101", "Object Oriented Programming"),
    ("Faculty of Computing and Informatics", "SWE2102", "Requirements Engineering"),
    ("Faculty of Computing and Informatics", "SWE2103", "Probability and Statistics"),
    (
        "Faculty of Computing and Informatics",
        "SWE2104",
        "Data Structure and Algorithms",
    ),
    (
        "Faculty of Computing and Informatics",
        "SWE2105",
        "Geographic Information Systems",
    ),
    (
        "Faculty of Computing and Informatics",
        "SWE2106",
        "Internet Technology and Web Design",
    ),
    ("Faculty of Computing and Informatics", "SWE2107", "Systems Analysis And Design"),
    ("Faculty of Computing and Informatics", "SWE3101", "Human Computer Interaction"),
    (
        "Faculty of Computing and Informatics",
        "SWE3102",
        "Software reliability and testing",
    ),
    ("Faculty of Computing and Informatics", "SWE3103", "Software Project Management"),
    ("Faculty of Computing and Informatics", "SWE3104", "Modeling and Simulation"),
    (
        "Faculty of Computing and Informatics",
        "SWE3105",
        "Research Methods in Computing",
    ),
    (
        "Faculty of Computing and Informatics",
        "SWE3107",
        "Mobile Networks and Computing",
    ),
    ("Faculty of Computing and Informatics", "SWE4101", "Computer Aided Design"),
    (
        "Faculty of Computing and Informatics",
        "SWE4102",
        "Computer Graphics Engineering",
    ),
    ("Faculty of Computing and Informatics", "SWE4103", "Formal methods"),
    ("Faculty of Computing and Informatics", "SWE4104", "Software Design Patterns"),
    (
        "Faculty of Computing and Informatics",
        "SWE4106",
        "Software Engineering Industrial Mini Project II",
    ),
    (
        "Faculty of Computing and Informatics",
        "SWE4107",
        "Client Server Programming for Applications",
    ),
)

#: Suggested questions for the six pilot units, by unit code.
#:
#: **Provisional until MUST confirms the launch catalogue.** These are the units a
#: first- or second-year student is most likely to ask for help with, and the
#: labels are phrased as the student would say them rather than as syllabus
#: headings. A label becomes the request's topic verbatim when tapped, so it has
#: to read like a question somebody would actually send: "SQL SELECT queries",
#: not "SQL/DQL". Adjusting a list is a data change, not a code change.
COURSE_UNIT_TOPICS: dict[str, tuple[str, ...]] = {
    "BIT1101": (
        "Computer hardware and peripherals",
        "Operating system basics",
        "Word processing and spreadsheets",
        "Internet and email",
        "Computer lab practicals",
        "ICT terminology",
    ),
    "BIT1103": (
        "Pointers and memory",
        "Arrays and strings",
        "Loops and conditionals",
        "Functions and recursion",
        "Structures and typedef",
        "File handling in C",
        "Debugging a C program",
    ),
    "BIT1105": (
        "Matrices and determinants",
        "Sets and logic",
        "Functions and graphs",
        "Sequences and series",
        "Probability basics",
        "Number bases",
    ),
    "BIT1106": (
        "Lists and dictionaries",
        "Loops and conditionals",
        "Functions and modules",
        "Classes and objects",
        "Exceptions and debugging",
        "File handling in Python",
    ),
    "BIT2103": (
        "ER diagrams",
        "Normalisation",
        "SQL SELECT queries",
        "Joins and subqueries",
        "Transactions and ACID",
        "Indexes and query plans",
        "Database design project",
    ),
    "BIT2107": (
        "Requirements gathering",
        "Use case and UML diagrams",
        "Agile and Scrum",
        "Software testing",
        "Design patterns",
        "Version control with Git",
        "Project documentation",
    ),
}


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
    faculty_names = {name for name, _description in FACULTIES}
    subjects = {
        row.name: row
        for row in (
            await db.execute(select(Subject).where(Subject.name.in_(faculty_names)))
        ).scalars()
    }
    legacy = await db.scalar(
        select(Subject).where(
            Subject.name == "Faculty of Computing and Informatics Sciences"
        )
    )
    if legacy is not None:
        legacy.name = "Faculty of Computing and Informatics"
        subjects[legacy.name] = legacy
    for name, description in FACULTIES:
        subject = subjects.get(name)
        if subject is None:
            subject = Subject(
                name=name,
                description=description,
            )
            db.add(subject)
            subjects[name] = subject
        else:
            subject.description = description
    await db.flush()
    return subjects


async def _seed_university(db: AsyncSession, scale: GradingScale) -> University:
    """MUST, attached to the scale its grades are awarded on."""
    university = await db.scalar(
        select(University).where(University.name == UNIVERSITY_NAME)
    )
    if university is None:
        university = await db.scalar(
            select(University).where(University.name == "Makerere University")
        )
        if university is not None:
            university.name = UNIVERSITY_NAME
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


async def _seed_course_unit_topics(
    db: AsyncSession, university: University
) -> tuple[int, list[str]]:
    """The pilot units' suggested questions. Returns the count and any miss.

    Idempotent: a label the unit already has is left in place, and only its order
    is corrected. A unit code that is not in the catalogue is reported rather than
    skipped silently, because a topic list attached to nothing is invisible from
    the student's side and has no other symptom.
    """
    added = 0
    missing: list[str] = []
    for code, labels in COURSE_UNIT_TOPICS.items():
        unit = await db.scalar(
            select(CourseUnit).where(
                CourseUnit.university_id == university.id,
                CourseUnit.code == code,
            )
        )
        if unit is None:
            missing.append(code)
            continue

        existing = {
            topic.label: topic
            for topic in (
                await db.execute(
                    select(CourseUnitTopic).where(
                        CourseUnitTopic.course_unit_id == unit.id
                    )
                )
            )
            .scalars()
            .all()
        }
        for order, label in enumerate(labels):
            topic = existing.get(label)
            if topic is None:
                db.add(
                    CourseUnitTopic(
                        course_unit_id=unit.id,
                        label=label,
                        sort_order=order,
                    )
                )
                added += 1
            elif topic.sort_order != order:
                topic.sort_order = order
    await db.flush()
    return added, sorted(missing)


async def _seed_programs(
    db: AsyncSession,
    university: University,
    subjects: dict[str, Subject],
) -> int:
    """Seed MUST's faculty programs without turning them into course units."""
    added = 0
    for faculty_name, level, name in PROGRAMS:
        subject = subjects[faculty_name]
        existing = await db.scalar(
            select(Program).where(
                Program.university_id == university.id,
                Program.faculty_id == subject.id,
                Program.name == name,
            )
        )
        if existing is None:
            db.add(
                Program(
                    name=name,
                    level=level,
                    university_id=university.id,
                    faculty_id=subject.id,
                )
            )
            added += 1
    await db.flush()
    return added


async def seed(db: AsyncSession) -> None:
    """Fill in the pilot's reference data and report what it did."""
    scale = await _seed_grading_scale(db)
    subjects = await _seed_subjects(db)
    university = await _seed_university(db, scale)
    for subject in subjects.values():
        subject.university_id = university.id
    await db.flush()
    added, orphans = await _seed_course_units(db, university, subjects)
    topics_added, topic_orphans = await _seed_course_unit_topics(db, university)
    programs_added = await _seed_programs(db, university, subjects)
    await db.commit()

    print(f"Seeded {UNIVERSITY_NAME}")
    print(
        f"  grading scale : {SCALE_NAME} "
        f"(max {MAX_POINTS}, gate {COMPETENCY_MIN_POINTS})"
    )
    print(f"  grades        : {', '.join(label for label, _ in GRADES)}")
    print(f"  faculties     : {len(subjects)}")
    print(f"  programs      : {programs_added} added")
    print(f"  course units  : {added} added")
    print(f"  unit topics   : {topics_added} added")
    if orphans:
        # Loud rather than silent: a unit with no faculty is invisible in the
        # wizard's faculty filter, which looks like a bug from the student's
        # side and has no other symptom.
        print(f"  WARNING: no faculty row for {', '.join(orphans)}")
    if topic_orphans:
        print(f"  WARNING: topics named for missing units {', '.join(topic_orphans)}")


def main() -> None:
    """Entry point for `python -m app.db.seed`."""

    async def _run() -> None:
        async with get_session_factory()() as session:
            await seed(session)

    asyncio.run(_run())


if __name__ == "__main__":
    main()

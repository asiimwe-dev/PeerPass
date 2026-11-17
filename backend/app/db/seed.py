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
import re
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

#: Which programme a code prefix belongs to.
#:
#: Used only to place catalogue rows that predate `course_units.program_id`, such
#: as a pilot database holding `BIT 221` instead of `BIT1101`. New rows carry
#: their programme in `COURSE_UNITS`; this map keeps a stale database from
#: keeping a second, unprogrammed copy of the same shelf.
PROGRAM_CODE_PREFIXES: dict[str, str] = {
    "BIT": "Information Technology",
    "CSC": "Computer Science",
    "SWE": "Software Engineering",
}

#: The FCI undergraduate catalogue from PR #39: `(programme, code, name)`.
#:
#: A unit belongs to the programme that publishes it, and a programme belongs to
#: the faculty that owns it, so the faculty is not repeated here. Codes differ
#: per programme (`BIT`, `CSC`, `SWE`), which is why the programme is data and
#: not something a request can infer from a code.
#:
#: The pilot intentionally excludes postgraduate degrees and non-FCI faculties.
#: A unit every programme takes is a real case (see `CourseUnit.program_id`), but
#: it is not how this catalogue is built: every row here belongs to one programme.
COURSE_UNITS: tuple[tuple[str, str, str], ...] = (
    ("Information Technology", "BIT1101", "Fundamentals of ICT"),
    ("Information Technology", "BIT1103", "Principles of Programming: C"),
    ("Information Technology", "BIT1104", "Fundamentals of Information Systems"),
    ("Information Technology", "BIT1105", "Mathematics for Information Technology"),
    ("Information Technology", "BIT1106", "Principals of Programming: Python"),
    ("Information Technology", "BIT1206", "Advanced Python Programming"),
    ("Information Technology", "BIT2101", "Object Oriented Programming 2"),
    ("Information Technology", "BIT2102", "Systems Security"),
    ("Information Technology", "BIT2103", "Database Management Systems"),
    ("Information Technology", "BIT2104", "Computer Networking"),
    ("Information Technology", "BIT2105", "Financial Management for IT professionals"),
    ("Information Technology", "BIT2106", "Agile Project Management"),
    ("Information Technology", "BIT2107", "Software Engineering"),
    ("Information Technology", "BIT3101", "Human Computer Interaction"),
    ("Information Technology", "BIT3103", "Geographic Information Systems"),
    ("Information Technology", "BIT3104", "Artificial Intelligence"),
    ("Information Technology", "BIT3105", "Mobile computing and Data communications"),
    ("Information Technology", "BIT3106", "Innovations and Entrepreneurship in IT"),
    ("Information Technology", "BIT3107", "Sensor Technologies"),
    (
        "Information Technology",
        "BIT3108",
        "Organizational Management for IT professionals",
    ),
    ("Computer Science", "CSC1101", "Computer Skills"),
    ("Computer Science", "CSC1102", "Principles of Programming"),
    ("Computer Science", "CSC1103", "Computer Organisation and Architecture"),
    (
        "Computer Science",
        "CSC1104",
        "Communication and Writing Skills for Computer Scientists",
    ),
    ("Computer Science", "CSC1114", "Communication Skills"),
    ("Computer Science", "CSC1121", "Computer Skills"),
    ("Computer Science", "CSC2101", "Operating Systems"),
    ("Computer Science", "CSC2102", "Object Oriented Programming- Java II"),
    ("Computer Science", "CSC2104", "Database programming"),
    ("Computer Science", "CSC2105", "Systems Analysis and Design"),
    ("Computer Science", "CSC2106", "Scientific Thinking"),
    ("Computer Science", "CSC3101", "Software Project Management"),
    ("Computer Science", "CSC3102", "Artificial Intelligence"),
    ("Computer Science", "CSC3103", "Embedded Systems"),
    ("Computer Science", "CSC3104", "Computational Complexity"),
    ("Computer Science", "CSC3105", "Multimedia Technology"),
    ("Computer Science", "CSC3106", "Wireless and Mobile Communications"),
    ("Computer Science", "CSC3109", "Mobile Applications Development"),
    ("Computer Science", "CSC3111", "Computer Vision & Image Processing"),
    ("Software Engineering", "SWE1101", "DISCRETE MATHEMATICS"),
    ("Software Engineering", "SWE1103", "Linear Algebra"),
    ("Software Engineering", "SWE1104", "Software Development Principles"),
    ("Software Engineering", "SWE1105", "COMMUNICATION SKILLS"),
    ("Software Engineering", "SWE2101", "Object Oriented Programming"),
    ("Software Engineering", "SWE2102", "Requirements Engineering"),
    ("Software Engineering", "SWE2103", "Probability and Statistics"),
    ("Software Engineering", "SWE2104", "Data Structure and Algorithms"),
    ("Software Engineering", "SWE2105", "Geographic Information Systems"),
    ("Software Engineering", "SWE2106", "Internet Technology and Web Design"),
    ("Software Engineering", "SWE2107", "Systems Analysis And Design"),
    ("Software Engineering", "SWE3101", "Human Computer Interaction"),
    ("Software Engineering", "SWE3102", "Software reliability and testing"),
    ("Software Engineering", "SWE3103", "Software Project Management"),
    ("Software Engineering", "SWE3104", "Modeling and Simulation"),
    ("Software Engineering", "SWE3105", "Research Methods in Computing"),
    ("Software Engineering", "SWE3107", "Mobile Networks and Computing"),
    ("Software Engineering", "SWE4101", "Computer Aided Design"),
    ("Software Engineering", "SWE4102", "Computer Graphics Engineering"),
    ("Software Engineering", "SWE4103", "Formal methods"),
    ("Software Engineering", "SWE4104", "Software Design Patterns"),
    (
        "Software Engineering",
        "SWE4106",
        "Software Engineering Industrial Mini Project II",
    ),
    ("Software Engineering", "SWE4107", "Client Server Programming for Applications"),
)

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
    db: AsyncSession,
    university: University,
    programs: dict[str, Program],
) -> tuple[int, int, list[str], list[str]]:
    """The starting catalogue.

    Returns the counts added and re-scoped, any programme a row named that does
    not exist, and any unit in a programme's faculty left without one.
    """
    existing = {
        unit.code: unit
        for unit in (
            await db.execute(
                select(CourseUnit).where(CourseUnit.university_id == university.id)
            )
        ).scalars()
    }

    added = 0
    updated = 0
    missing_programs: set[str] = set()
    for program_name, code, name in COURSE_UNITS:
        program = programs.get(program_name)
        if program is None:
            missing_programs.add(program_name)
            continue
        unit = existing.get(code)
        if unit is None:
            db.add(
                CourseUnit(
                    code=code,
                    name=name,
                    university_id=university.id,
                    subject_id=program.faculty_id,
                    program_id=program.id,
                    # `grade_id` is left null deliberately. A unit awards a range
                    # of grades, not one, and the grade a student actually got is
                    # named by their `Competency`. Assigning a single grade to
                    # every unit would invent data that the model already has a
                    # correct place for. The unit's scale is inherited from its
                    # university either way, which is what the matching engine
                    # reads.
                    grade_id=None,
                )
            )
            added += 1
        elif unit.program_id is None:
            # A catalogue row from before programmes existed. Its own programme
            # is known from the list it is in, so this is a correction and not a
            # guess.
            unit.program_id = program.id
            updated += 1

    # Codes that predate the current catalogue entirely -- a pilot database with
    # `BIT 221` rather than `BIT1101`. The prefix is the only thing that knows
    # which programme they belong to, and it is only trusted inside the faculty
    # that owns them.
    for unit in existing.values():
        if unit.program_id is not None:
            continue
        prefix = re.match(r"[A-Z]+", unit.code)
        program = (
            programs.get(PROGRAM_CODE_PREFIXES.get(prefix.group(0), ""))
            if prefix
            else None
        )
        if program is not None and unit.subject_id == program.faculty_id:
            unit.program_id = program.id
            updated += 1

    faculty_ids = {program.faculty_id for program in programs.values()}
    unassigned = sorted(
        unit.code
        for unit in existing.values()
        if unit.program_id is None
        and unit.subject_id is not None
        and unit.subject_id in faculty_ids
    )
    await db.flush()
    return added, updated, sorted(missing_programs), unassigned


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
) -> dict[str, Program]:
    """Seed MUST's faculty programmes, keyed by name.

    Seeded before the catalogue: a course unit is published by a programme, so
    the programme has to exist before a unit can point at it.
    """
    programs = {
        row.name: row
        for row in (
            await db.execute(
                select(Program).where(Program.university_id == university.id)
            )
        ).scalars()
    }
    for faculty_name, level, name in PROGRAMS:
        subject = subjects[faculty_name]
        if name not in programs:
            program = Program(
                name=name,
                level=level,
                university_id=university.id,
                faculty_id=subject.id,
            )
            db.add(program)
            programs[name] = program
    await db.flush()
    return programs


async def seed(db: AsyncSession) -> None:
    """Fill in the pilot's reference data and report what it did."""
    scale = await _seed_grading_scale(db)
    subjects = await _seed_subjects(db)
    university = await _seed_university(db, scale)
    for subject in subjects.values():
        subject.university_id = university.id
    await db.flush()
    programs = await _seed_programs(db, university, subjects)
    added, updated, missing_programs, unassigned = await _seed_course_units(
        db, university, programs
    )
    topics_added, topic_orphans = await _seed_course_unit_topics(db, university)
    await db.commit()

    print(f"Seeded {UNIVERSITY_NAME}")
    print(
        f"  grading scale : {SCALE_NAME} "
        f"(max {MAX_POINTS}, gate {COMPETENCY_MIN_POINTS})"
    )
    print(f"  grades        : {', '.join(label for label, _ in GRADES)}")
    print(f"  faculties     : {len(subjects)}")
    print(f"  programmes    : {len(programs)}")
    print(f"  course units  : {added} added, {updated} scoped to a programme")
    print(f"  unit topics   : {topics_added} added")
    if missing_programs:
        # A data error rather than a state to handle: the table names a
        # programme that does not exist, and those units are not seeded at all.
        print(
            "  WARNING: catalogue rows name missing programmes "
            f"{', '.join(missing_programs)}"
        )
    if unassigned:
        # An unprogrammed unit inside a programme's faculty is visible to every
        # student in that faculty, which looks like a leaking catalogue and has
        # no other symptom from the student's side.
        print(f"  WARNING: units left without a programme {', '.join(unassigned)}")
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

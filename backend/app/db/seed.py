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
from app.models.course_unit import CourseUnit, Program, Subject, University
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
        "Faculty of Medicine",
        "The founding and most prominent faculty, offering health sciences "
        "undergraduate and postgraduate education.",
    ),
    (
        "Faculty of Science",
        "Focuses on basic and applied sciences, including biology, chemistry, "
        "mathematics, and physics.",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "Drives technology education through computing, information technology, "
        "and postgraduate information systems programs.",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "Offers engineering and industrial programs, including biomedical, "
        "electrical and electronics, petroleum, and environmental programs.",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "Focuses on community development and applied interdisciplinary programs.",
    ),
    (
        "Faculty of Business and Management Sciences",
        "Provides business education tailored to science and technology sectors.",
    ),
)

PROGRAMS: tuple[tuple[str, str, str], ...] = (
    ("Faculty of Medicine", "undergraduate", "Medicine and Surgery (MBChB)"),
    ("Faculty of Medicine", "postgraduate", "Master of Medicine (MMed)"),
    (
        "Faculty of Computing and Informatics Sciences",
        "undergraduate",
        "Computer Science",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "postgraduate",
        "Health Information Technology",
    ),
)

#: The provisional MUST pilot catalogue: `(faculty, code, name)`.
#:
#: These are the only units currently eligible for the closed pilot. They are
#: seed entries, not an institutional endorsement or a claim that MUST's full
#: catalogue has been loaded. Do not derive more units from programme names:
#: programmes and matchable course units are different records.
#:
#: Every faculty MUST publishes has at least one unit here. A faculty with an
#: empty catalogue cannot be declared against, so a student in one could never
#: apply to tutor -- the pilot would look like a broken feature rather than an
#: empty one. `tests/test_cli.py` fails if a faculty is added without a unit.
#:
#: **The codes are provisional and are not MUST course codes.** MUST does not
#: publish a course-unit catalogue: `must.ac.ug` programme pages carry faculty,
#: course code, duration and entry requirements, but their "Course Modules" tab
#: is empty, and no module list is published anywhere public. The names below
#: are drawn from MUST's own academic units -- the departments listed on each
#: faculty page -- because a department is a real, verifiable academic unit
#: where a programme name is not, and its subject areas are what its first-year
#: courses teach. Replace the whole table with the official catalogue when MUST
#: supplies one; nothing else in the codebase encodes a code or a name.
#:
#: Sources, retrieved for this seed:
#:
#: * `must.ac.ug/university_unit/faculty-of-medicine` and its Biochemistry
#:   department page, which states biochemistry is "a mandatory course for all
#:   students in the faculty".
#: * `must.ac.ug/university_unit/faculty-of-applied-sciences-and-technology`,
#:   which lists the Department of Electrical and Electronic Engineering, and the
#:   BEEE programme page, whose entry requirements name Technical Drawing.
#: * `must.ac.ug/university_unit/faculty-of-business-and-management-sciences`,
#:   which lists the Departments of Accounting and Finance and of Economics and
#:   Entrepreneurship.
#: * `must.ac.ug/university_unit/faculty-of-interdisciplinary-studies`, which
#:   lists its four departments by name.
#:
#: Note that MUST's own site now calls this faculty "Faculty of Health Sciences"
#: and lists a seventh faculty, Agriculture, Environment and Veterinary Sciences.
#: The seed keeps the older names because renaming a seeded faculty would orphan
#: every course unit, declared module and competency keyed to it.
COURSE_UNITS: tuple[tuple[str, str, str], ...] = (
    (
        "Faculty of Applied Sciences and Technology",
        "BCE1111",
        "Engineering Mathematics I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE1113",
        "Information & Communication Technology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE2102",
        "Digital Systems",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE2111",
        "Engineering Mathematics III",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE2113",
        "Object Orineted Programming java",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE3110",
        "Communication Systems Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE3121",
        "VLSI Systems and Design",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE3123",
        "Internet of Things",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE4107",
        "Optical Communication Systems",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE4112",
        "Control Systems Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE4113",
        "Engineering Project Planning and Management",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME1104",
        "Engineering Physics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME2104",
        "Human Anatomy & Physiology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME2105",
        "Biomaterials and Biocompatibility",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME2111",
        "Workshop Practice I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME3101",
        "Microprocessors",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME3110",
        "Bioteletry & Telemedicine",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME3111",
        "BME Workshop Practice III",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME3112",
        "Neuroscience and Neural Networks",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME3113",
        "Biosensing and Measurements",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME4101",
        "Medical Imaging Systems II",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME4106",
        "Biomedical Signal and Image Processing",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME4110",
        "Rehabilitative & Assistive Technology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "BME4111",
        "Machine Learning & Pattern Recognition",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE1102",
        "Introduction to Civil Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE1103",
        "Engineering Mechanics I (Statics)",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE1104",
        "Civil Engineering Drawing",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE2103",
        "Geotechnical Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE2104",
        "Engineering Geology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE2105",
        "Theory of Structures I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE2106",
        "Engineering Surveying I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE3101",
        "Civil Engineering Materials",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE3102",
        "Highway Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE3103",
        "Construction Technology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE3104",
        "Hydrology I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE3105",
        "Design of Structures I (Concrete)",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE4102",
        "Principles of Quantity Surveying",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE4103",
        "Public Health Engineering II",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE4104",
        "Civil Engineering Infrastructure Maintenance",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE4105",
        "Design Of Structures III (Timber And Masonry)",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE4106",
        "Advanced Structural Analysis",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE1101",
        "Electricity and Magnetism",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE1105",
        "Physical Electronics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE1111",
        "Engineering Materials",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE2102",
        "Electronic Circuits",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE2104",
        "Electrical Machine Design",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE2106",
        "Engineering Ethics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE2112",
        "Control and Instrumentation",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE2114",
        "Simulation & Testing Engineeing",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE3111",
        "Semiconductor Devices and Applications",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE3112",
        "Analog Electronics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE3115",
        "Renewable Energy Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE4102",
        "Maintenance Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE4104",
        "TV and Video Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE4105",
        "Electrical Installation Design",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "EEE4113",
        "Power Generation, Operation and Control",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "FME4111",
        "Introduction to Family Medicine and Community Practice",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "GWH2105",
        "Gender Mainstreaming",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "GWH3101",
        "International agenda and women health",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "GWH3102",
        "Principles of Health Education",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "GWH3104",
        "Women Health Promotion Strategies",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "GWH3110",
        "Adolescent Development and Health Promotion",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "GWH3113",
        "Social Determinants of Population Health",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE1102",
        "Engineering Mechanics I (Statics)",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE1106",
        "Production Engineering I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE2102",
        "Mechanics Of Materials I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE2104",
        "Fluid Mechanics I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE2105",
        "Plant Layout and Material Handling",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE2106",
        "Principles of Mechatronics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE2107",
        "Quality and Reliability Engineering,",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE3101",
        "Product Design and Development",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE3102",
        "Dynamic Systems Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE3103",
        "Materials Science and Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE3104",
        "Theory of Machines",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE3105",
        "Applied Thermodynamics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE4102",
        "Production Planning and Inventory Control",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE4103",
        "Maintenance Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE4104",
        "Fluid Power Systems",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE4105",
        "Introduction to Robotics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE4106",
        "Finite Element Analysis in Mechanical Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "MIE4107",
        "Renewable Energy Technology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM1101",
        "Fundamentals of Environmental Management",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM1102",
        "Applied Physics I",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM1104",
        "Fundamentals of Petroleum Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM1105",
        "Applied Biodiversity",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM2101",
        "Sedimentology & Stratigraphy",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM2102",
        "Computer Aided Design / MIE2103 Computer-Aided Design for Mechanical Engineers",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM2103",
        "Petroleum Geology",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM2104",
        "Geophysics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM2105",
        "Fluid Mechanics",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM2106",
        "Workshop Practice II",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3101",
        "HSE Management in Oil and Gas Industry",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3102",
        "Reservoir Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3103",
        "Well Logging and Integrated Interpretation",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3104",
        "Drilling Engineering II",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3105",
        "Research methods",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3106",
        "Procurement, Logistics & Supply Chain Management for Engineers",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3107",
        "Process Dynamics and Control",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM3108",
        "Reservoir Characterization and Modeling",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4101",
        "Petroleum Production Engineering II",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4102",
        "Petroleum Economics and Management",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4103",
        "Gas Reservoir Engineering",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4104",
        "Numerical Reservoir Simulation",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4105",
        "Principles of Enhanced Oil Recovery",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4106",
        "Technology of Artificil Lift Methods",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "PEM4107",
        "Principles of Modern Well Testing and Interpretation",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "STP2101",
        "Students' Community Twinning Project",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "STP3110",
        "Students' Community Twinning Project",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA1101",
        "Business Quantitative methods",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA1102",
        "Business Communication Skills",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA1103",
        "Principles of Business Economics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA1104",
        "Principles of Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA1105",
        "Principles of ICT",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2101",
        "Intermediate Accounting",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2102",
        "Company Law",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2103",
        "/ BBA2103 Principles of Human Resource Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2104",
        "Insurance II - General Insurance",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2105",
        "Organisational Behavior",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2106",
        "Taxation I",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA2107",
        "Principles of Entrepreneurship",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3102",
        "Strategic Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3103",
        "Business and Corporate Governance",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3104",
        "Auditing",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3105",
        "Taxation II",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3106",
        "Banking and Financial Services",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3107",
        "International Financial Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3108",
        "Marketing Channels",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3109",
        "Marketing Research",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3110",
        "Rewards and Compensation Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3111",
        "Industrial Psychology",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3112",
        "E - Procurement",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BBA3113",
        "International Procurement Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC1101",
        "Basic Microeconomics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC1102",
        "Elements of Mathematics for Economists",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC1103",
        "History of Economic Doctrines",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC2101",
        "Microeconomics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC2102",
        "Mathematical Economics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC2103",
        "Econometrics and Computing for Economists.",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC2104",
        "Statistical Quality Control",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC2105",
        "Health Economics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC3101",
        "Intermediate Microeconomics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC3102",
        "Applied Econometrics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC3103",
        "Monitoring and Evaluation",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC3104",
        "Monetary and Financial Economics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC3105",
        "Labour and Industrial Economics",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BEC3107",
        "Transport Economics and Logistics Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF1101",
        "Introduction to Financial Accounting",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF1106",
        "Principles of ICT",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF2101",
        "Financial Aaccounting II",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF2114",
        "Taxation I",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF2115",
        "Critical Thinking and Logic",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF3126",
        "Advanced Cost and Management Accounting",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF3127",
        "Investment Analysis and Portifolio Management",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF3128",
        "Computerized Accounting",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF3130",
        "Audit and Assurance",
    ),
    (
        "Faculty of Business and Management Sciences",
        "BSAF3131",
        "Insurance II",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT1101",
        "Fundamentals of ICT",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT1103",
        "Principles of Programming: C",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT1104",
        "Fundamentals of Information Systems",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT1105",
        "Mathematics for Information Technology",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT1106",
        "Principals of Programming: Python",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT1206",
        "Advanced Python Programming",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2101",
        "Object Oriented Programming 2",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2102",
        "Systems Security",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2103",
        "Database Management Systems",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2104",
        "Computer Networking",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2105",
        "Financial Management for IT professionals",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2106",
        "Agile Project Management",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT2107",
        "Software Engineering",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3101",
        "Human Computer Interaction",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3103",
        "Geographic Information Systems",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3104",
        "Artificial Intelligence",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3105",
        "Mobile computing and Data communications",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3106",
        "Innovations and Entrepreneurship in IT",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3107",
        "Sensor Technologies",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "BIT3108",
        "Organizational Management for IT professionals",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC1101",
        "Computer Skills",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC1102",
        "Principles of Programming",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC1103",
        "Computer Organisation and Architecture",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC1104",
        "Communication and Writing Skills for Computer Scientists",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC1114",
        "Communication Skills",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC1121",
        "Computer Skills",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC2101",
        "Operating Systems",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC2102",
        "Object Oriented Programming- Java II",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC2104",
        "Database programming",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC2105",
        "Systems Analysis and Design",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC2106",
        "Scientific Thinking",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3101",
        "Software Project Management",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3102",
        "Artificial Intelligence",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3103",
        "Embedded Systems",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3104",
        "Computational Complexity",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3105",
        "Multimedia Technology",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3106",
        "Wireless and Mobile Communications",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3109",
        "Mobile Applications Development",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "CSC3111",
        "Computer Vision & Image Processing",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "DCS1101",
        "Computer Skils",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE1101",
        "DISCRETE MATHEMATICS",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE1103",
        "Linear Algebra",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE1104",
        "Software Development Principles",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE1105",
        "COMMUNICATION SKILLS",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2101",
        "Object Oriented Programming",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2102",
        "Requirements Engineering",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2103",
        "Probability and Statistics",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2104",
        "Data Structure and Algorithms",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2105",
        "Geographic Information Systems",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2106",
        "Internet Technology and Web Design",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE2107",
        "Systems Analysis And Design",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE3101",
        "Human Computer Interaction",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE3102",
        "Software reliability and testing",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE3103",
        "Software Project Management",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE3104",
        "Modeling and Simulation",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE3105",
        "Research Methods in Computing",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE3107",
        "Mobile Networks and Computing",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE4101",
        "Computer Aided Design",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE4102",
        "Computer Graphics Engineering",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE4103",
        "Formal methods",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE4104",
        "Software Design Patterns",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE4106",
        "Software Engineering Industrial Mini Project II",
    ),
    (
        "Faculty of Computing and Informatics Sciences",
        "SWE4107",
        "Client Server Programming for Applications",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD1102",
        "Introduction to Interdisciplinary Studies",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD1106",
        "Fundamentals of Community Psychology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD1107",
        "Communication and Facilitation skills",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD1108",
        "Macro and Micro Economics",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD1109",
        "Fundamentals of Development, Plannining, Theory and Practice",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD2101",
        "Development Economics",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD2102",
        "Civil Society Organizations and Development",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD2104",
        "Planning Techniques",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3101",
        "Human Resource Planning",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3102",
        "Land Governance",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3103",
        "Rural economics",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3104",
        "Rural Livelihoods and Poverty Analysis",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3105",
        "Gender in Rural Development",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3106",
        "Project Planning and Management",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3107",
        "Approaches to Urban Development",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3108",
        "Public- Private Partnerships for Urban Service Delivery",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3110",
        "People Centered Urban Governance",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3111",
        "Social Costs of Urban Growth and Development",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BPCD3118",
        "Appraisal and Evaluation of Rural Development Projects and Programmes",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL1101",
        "Livelihoods Approaches for Agricultural Transformation",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL1102",
        "Agricultural Botany and Plant Physiology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL1104",
        "Crop Production Systems",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL1105",
        "Livestock Production Systems",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL1106",
        "Fundamentals Of Animal Anatomy And Physiology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL2101",
        "Farm Planning, Systems and structures",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL2102",
        "Pasture Production and Rangeland management",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL2103",
        "Animal Health and Disease",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL2104",
        "Entomology and Nematology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL2105",
        "Agricultural Production Economics",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL2106",
        "Animal Nutrition and Feed Technology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3103",
        "Small Ruminants",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3104",
        "Agricultural Project Planning and Management",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3105",
        "Farmer Institutional Structures and Development",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3106",
        "Farm Mechanization",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3107",
        "Application of Food Science and Innovation Systems",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3108",
        "Land Tenure, Use and Planning",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL3109",
        "Statistics for Agricultual Research",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL4101",
        "Farm Enterprise Development and Innovation Systems",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL4113",
        "Animal Breeding",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL4114",
        "Agricultural Vulnerability and Resilience",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL4115",
        "Entrepreneurship And Agricultural Marketing And Cooperatives",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL4116",
        "Plant Breeding And Biotechnology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "BSAL4117",
        "Milk And Meat Technology",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "DVS1106",
        "Introduction to Political Economy",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "DVS2105",
        "Political Economy of Uganda",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU1101",
        "Educational Development & Trends In East-Africa",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU1102",
        "Sociology of Education",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU1103",
        "Curriculum and Instruction",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU2102",
        "General Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU2103",
        "Mathematics Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU2104",
        "Physics Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU2105",
        "Chemistry Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU2106",
        "Biology Teaching Method",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU3101",
        "Educational Administration",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU3103",
        "Mathematics Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU3104",
        "Physics Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU3105",
        "Chemistry Teaching Methods",
    ),
    (
        "Faculty of Interdisciplinary Studies",
        "EDU3106",
        "Biology Teaching Methods",
    ),
    (
        "Faculty of Medicine",
        "ANA1121",
        "Gross Anatomy of Limbs and Thorax",
    ),
    (
        "Faculty of Medicine",
        "ANA1122",
        "Histology & Cytology I",
    ),
    (
        "Faculty of Medicine",
        "ANA1123",
        "Human Embryology & Teratology I",
    ),
    (
        "Faculty of Medicine",
        "ANA1125",
        "Systemic Anatomy I / Gross Anatomy, Embryology and Histology",
    ),
    (
        "Faculty of Medicine",
        "ANA2121",
        "Neuroanatomy & Special Sence Organs",
    ),
    (
        "Faculty of Medicine",
        "BCH1121",
        "Introduction to Biochemistry THEORY",
    ),
    (
        "Faculty of Medicine",
        "BCH1125",
        "Basic Biochemistry",
    ),
    (
        "Faculty of Medicine",
        "BCH2121",
        "Medical Biochemisty II / Metabolism and Metabolic Disorders II",
    ),
    (
        "Faculty of Medicine",
        "BCH2122",
        "Hormones, Biotransformation and Nutrition",
    ),
    (
        "Faculty of Medicine",
        "BCH3128",
        "Genetic Engineering",
    ),
    (
        "Faculty of Medicine",
        "CMH1121",
        "Biostatistics and Demography",
    ),
    (
        "Faculty of Medicine",
        "CMH3121",
        "Control of Communicable and Non-Communicable Diseases",
    ),
    (
        "Faculty of Medicine",
        "CMH4111",
        "Research Methods",
    ),
    (
        "Faculty of Medicine",
        "CMH4112",
        "Maternal and Child Health",
    ),
    (
        "Faculty of Medicine",
        "CMH5111",
        "Occupational Health",
    ),
    (
        "Faculty of Medicine",
        "MCB2121",
        "Introduction to Microbiology THEORY",
    ),
    (
        "Faculty of Medicine",
        "MCB3121",
        "Pharmaceutical Microbiology",
    ),
    (
        "Faculty of Medicine",
        "MCB4121",
        "Pharmaceutical Microbiology",
    ),
    (
        "Faculty of Medicine",
        "MED3121",
        "Internal Medicine - Theory I",
    ),
    (
        "Faculty of Medicine",
        "MED4112",
        "Palliative Care",
    ),
    (
        "Faculty of Medicine",
        "MED4113",
        "Ethics and professionalism",
    ),
    (
        "Faculty of Medicine",
        "MED5111",
        "Internal Medicine - Theory II THEORY",
    ),
    (
        "Faculty of Medicine",
        "MLC2121",
        "Haematology. BT and Practical I: Haemopoiesis and Proliferative blood disorders",
    ),
    (
        "Faculty of Medicine",
        "MLC2122",
        "Microbiology and Practical II: Basic and Public Health Bacteriology",
    ),
    (
        "Faculty of Medicine",
        "MLC2123",
        "Parasitology and Practical I: Protozoology and Helminthology",
    ),
    (
        "Faculty of Medicine",
        "MLC2125",
        "Applied Molecular Biology, Bioinformatics and Animal House Science PRACTICAL",
    ),
    (
        "Faculty of Medicine",
        "MLC3121",
        "Clinical Chemistry and Practical II: Hormones and Organ Function Tests",
    ),
    (
        "Faculty of Medicine",
        "MLC3122",
        "Haematology, BT and Practical II: Coagulation and Immunohaematology PRACTICAL",
    ),
    (
        "Faculty of Medicine",
        "MLC3123",
        "Histopathology and Practical II: Histochemistry and immunohistochemistr",
    ),
    (
        "Faculty of Medicine",
        "MLC3124",
        "Microbiology and Practical II: Systematic Bacteriology",
    ),
    (
        "Faculty of Medicine",
        "MLC3125",
        "Parasitology and Practical II: Medical Entomology",
    ),
    (
        "Faculty of Medicine",
        "MLC3126",
        "Research Methods III: Data Collection, Analysis & Report",
    ),
    (
        "Faculty of Medicine",
        "MLC3127",
        "Laboratory Planning, Construction, layout and Procurement",
    ),
    (
        "Faculty of Medicine",
        "MLS1121",
        "Cell Biology and Genetics",
    ),
    (
        "Faculty of Medicine",
        "MLS2121",
        "Clinical Chemistry and Practical I (Introduction to Clinical Chemistry",
    ),
    (
        "Faculty of Medicine",
        "MLS2122",
        "Haematology I: Introduction to haematology &Blood Transfusion; Basic Haematological Practice",
    ),
    (
        "Faculty of Medicine",
        "MLS2123",
        "Histopathology and Practical I: Introduction to histopathology and histological stains",
    ),
    (
        "Faculty of Medicine",
        "MLS2124",
        "Microbiology and Practical I: Principles of Microbiology PRACTICAL",
    ),
    (
        "Faculty of Medicine",
        "MLS2125",
        "Parasitology and Practical I: Introduction to Medical Parasitology",
    ),
    (
        "Faculty of Medicine",
        "MLS3121",
        "Clinical Chemistry and Practical III Non Protein Nitrogenous Compounds (NPNs) & Enzymology",
    ),
    (
        "Faculty of Medicine",
        "MLS3122",
        "Haematology and practical III: Immunohaematology & Blood Banking",
    ),
    (
        "Faculty of Medicine",
        "MLS3123",
        "Histopathology and Practical III: (Cytology and Histochemistry)",
    ),
    (
        "Faculty of Medicine",
        "MLS3124",
        "Microbiology and Practical III: Applied Mycology and Diagnostic Virology",
    ),
    (
        "Faculty of Medicine",
        "MLS3125",
        "Parasitology and Practical III: Intestinal and Urogenital Protozoology PRACTICAL",
    ),
    (
        "Faculty of Medicine",
        "MLS3126",
        "/ MLC2124 Research Methods: Inroduction to Research",
    ),
    (
        "Faculty of Medicine",
        "MLS4121",
        "Clinical Chemistry and Practical V (Lipids, Haemoglobin and disease)",
    ),
    (
        "Faculty of Medicine",
        "MLS4122",
        "Haematology V: The White cell disorders - Diagnosis and Management",
    ),
    (
        "Faculty of Medicine",
        "MLS4123",
        "Histopathology and Practical V: Immunohistochemistry and traditional techniques. PRACTICAL",
    ),
    (
        "Faculty of Medicine",
        "MLS4124",
        "Microbiology and Practical V: Diagnostic Virology and Public Health Bacteriology",
    ),
    (
        "Faculty of Medicine",
        "MLS4125",
        "Parasitology and Practical V: Cestodes and Trematodes",
    ),
    (
        "Faculty of Medicine",
        "MLS4126",
        "Research Methods II: Proposal Development",
    ),
    (
        "Faculty of Medicine",
        "MLS4127",
        "Laboratory Planning, Construction, layout and Procurement",
    ),
    (
        "Faculty of Medicine",
        "NSG1111",
        "Introduction to Nursing",
    ),
    (
        "Faculty of Medicine",
        "NSG1112",
        "Clinical Nursing Skills",
    ),
    (
        "Faculty of Medicine",
        "NSG2115",
        "Pathophysiology",
    ),
    (
        "Faculty of Medicine",
        "NSG2116",
        "Health Assessment I",
    ),
    (
        "Faculty of Medicine",
        "NSG2117",
        "Humanistic Perspectives of Nursing",
    ),
    (
        "Faculty of Medicine",
        "NSG3118",
        "Midwifery (Labour/Peur/New Born) II",
    ),
    (
        "Faculty of Medicine",
        "NSG3120",
        "Medical - Surgical Nursing I",
    ),
    (
        "Faculty of Medicine",
        "NSG3121",
        "Paediatric Nursing I",
    ),
    (
        "Faculty of Medicine",
        "NSG3122",
        "Psychiatric Nursing I",
    ),
    (
        "Faculty of Medicine",
        "NSG3123",
        "Nursing in the Community",
    ),
    (
        "Faculty of Medicine",
        "NSG4118",
        "Midwifery (GYN)",
    ),
    (
        "Faculty of Medicine",
        "NSG4124",
        "Nursing Research II [Theory and Proposal Development]",
    ),
    (
        "Faculty of Medicine",
        "NSG4125",
        "Nursing Education",
    ),
    (
        "Faculty of Medicine",
        "NSG4126",
        "Nursing Administration and Management Ward Attachment",
    ),
    (
        "Faculty of Medicine",
        "NSG4127",
        "Sociology & Anthropology",
    ),
    (
        "Faculty of Medicine",
        "NSG4229",
        "TRADITIONAL MEDICINE / COMPLEMENTARY THERAPIES",
    ),
    (
        "Faculty of Medicine",
        "OBG3121",
        "Obstetrics and Gynaecology - Theory I",
    ),
    (
        "Faculty of Medicine",
        "OBG3122",
        "/ SUG3122 /PCH3122 /MED3122",
    ),
    (
        "Faculty of Medicine",
        "OBG5111",
        "Obstetrics and Gynaecology-Theory II/ SUG5111 Surgery- Theory II THEORY",
    ),
    (
        "Faculty of Medicine",
        "OBG5112",
        "/SUG5112 /PCH5112 /MED5112",
    ),
    (
        "Faculty of Medicine",
        "PAT2111",
        "General Pathology I / PHX2122 Introduction to Pathology",
    ),
    (
        "Faculty of Medicine",
        "PAT3121",
        "Systemic Pathology I",
    ),
    (
        "Faculty of Medicine",
        "PAT4111",
        "Forensic Medicine",
    ),
    (
        "Faculty of Medicine",
        "PCH3121",
        "Paediatrics and Child Health Theory I",
    ),
    (
        "Faculty of Medicine",
        "PCH3122",
        "/ SUG3122 / OBG3122 / MED3122",
    ),
    (
        "Faculty of Medicine",
        "PCH5111",
        "Paediatrics and Child Health - Theory II",
    ),
    (
        "Faculty of Medicine",
        "PHA2121",
        "Basic Pharmacology",
    ),
    (
        "Faculty of Medicine",
        "PHA3122",
        "Chemotherapy, Cytoxic agents and Immunopharmacology",
    ),
    (
        "Faculty of Medicine",
        "PHC1111",
        "Heath Promotions",
    ),
    (
        "Faculty of Medicine",
        "PHC1112",
        "/ PHX2124 Exercise Science",
    ),
    (
        "Faculty of Medicine",
        "PHC1113",
        "Diagnostic Radiography",
    ),
    (
        "Faculty of Medicine",
        "PHC1114",
        "Professional Care and Rehabilitation Studies",
    ),
    (
        "Faculty of Medicine",
        "PHC2101",
        "Clinical Placement A",
    ),
    (
        "Faculty of Medicine",
        "PHS1121",
        "Physiology I / Excitable tissues and circulatory system Physiology",
    ),
    (
        "Faculty of Medicine",
        "PHS1123",
        "Excitable tissues, blood and Cardiopulmonary Physiology",
    ),
    (
        "Faculty of Medicine",
        "PHS2121",
        "Physiology III THEORY",
    ),
    (
        "Faculty of Medicine",
        "PHX1121",
        "Physiotherapy, Professionalism & Communication",
    ),
    (
        "Faculty of Medicine",
        "PHX1122",
        "Advanced Study Skills",
    ),
    (
        "Faculty of Medicine",
        "PHX2123",
        "Applied Physics & Electro-Physical Modalities",
    ),
    (
        "Faculty of Medicine",
        "PHX3112",
        "Rehabilitation Studies",
    ),
    (
        "Faculty of Medicine",
        "PHX3113",
        "Cardiopulmonary Rehabilitation",
    ),
    (
        "Faculty of Medicine",
        "PHX3114",
        "Paediatric Rehabilitation",
    ),
    (
        "Faculty of Medicine",
        "PHX3115",
        "Research Methods",
    ),
    (
        "Faculty of Medicine",
        "PHX3116",
        "Clinical Practice A",
    ),
    (
        "Faculty of Medicine",
        "PHX4111",
        "Sports Rehabilitation",
    ),
    (
        "Faculty of Medicine",
        "PHX4112",
        "Advanced Clinical Management",
    ),
    (
        "Faculty of Medicine",
        "PHX4113",
        "Business Management and Administration",
    ),
    (
        "Faculty of Medicine",
        "PHX4114",
        "Pharmacology for Physiotherapists",
    ),
    (
        "Faculty of Medicine",
        "PHX4115",
        "Research Project II",
    ),
    (
        "Faculty of Science",
        "BIO1101",
        "Cell biology and Genetics",
    ),
    (
        "Faculty of Science",
        "BIO1102",
        "Lower Plants' Systematics",
    ),
    (
        "Faculty of Science",
        "BIO1103",
        "Protist & Invertebrate Systematics",
    ),
    (
        "Faculty of Science",
        "BIO1104",
        "Practical one: Instrumentation, Cytology & invertebrates' identification",
    ),
    (
        "Faculty of Science",
        "BIO2101",
        "Fundamentals of Ecology",
    ),
    (
        "Faculty of Science",
        "BIO2102",
        "Plant Physiology",
    ),
    (
        "Faculty of Science",
        "BIO2103",
        "Microbiology & Biotechnology",
    ),
    (
        "Faculty of Science",
        "BIO2104",
        "Ichthyology & Herpetology",
    ),
    (
        "Faculty of Science",
        "BIO2105",
        "Practical three: Microorganisms' identification & Plant/Animals structures",
    ),
    (
        "Faculty of Science",
        "BIO3101",
        "Hydrobiology",
    ),
    (
        "Faculty of Science",
        "BIO3102",
        "Animal Histology",
    ),
    (
        "Faculty of Science",
        "BIO3103",
        "Animal Physiology",
    ),
    (
        "Faculty of Science",
        "BIO3104",
        "Plant Breeding & Crop Improvement",
    ),
    (
        "Faculty of Science",
        "BIO3105",
        "Practical five: Water quality and Animal's Physiology & histological investigations",
    ),
    (
        "Faculty of Science",
        "CHE1101",
        "Basic inorganic chemistry THEORY",
    ),
    (
        "Faculty of Science",
        "CHE1102",
        "Basic Physical Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE1103",
        "Mathematics for Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE2101",
        "Analytical Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE2102",
        "Chemical Thermodynamics",
    ),
    (
        "Faculty of Science",
        "CHE2103",
        "Protein and Sugar Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE3101",
        "Transitional, Quantum and Nuclear Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE3102",
        "Colloidal Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE3103",
        "Cyclic Chemistry",
    ),
    (
        "Faculty of Science",
        "CHE3104",
        "Stereochemistry and Physical Organic Chemistry",
    ),
    (
        "Faculty of Science",
        "MTH1101",
        "Discret Mathematics",
    ),
    (
        "Faculty of Science",
        "MTH1102",
        "Culculus I",
    ),
    (
        "Faculty of Science",
        "MTH1103",
        "Probability and Statistics",
    ),
    (
        "Faculty of Science",
        "MTH2101",
        "Differential equations",
    ),
    (
        "Faculty of Science",
        "MTH2102",
        "Linear Algebra II",
    ),
    (
        "Faculty of Science",
        "MTH2103",
        "Complex Analysis",
    ),
    (
        "Faculty of Science",
        "MTH2104",
        "Differential Equations I",
    ),
    (
        "Faculty of Science",
        "MTH3101",
        "Abstract Algebra",
    ),
    (
        "Faculty of Science",
        "MTH3102",
        "Real Analysis II",
    ),
    (
        "Faculty of Science",
        "MTH3103",
        "Numerical Analysis II",
    ),
    (
        "Faculty of Science",
        "MTH3104",
        "Statistics",
    ),
    (
        "Faculty of Science",
        "MTH3105",
        "Differential Equations II",
    ),
    (
        "Faculty of Science",
        "MTH3106",
        "Graph Theory",
    ),
    (
        "Faculty of Science",
        "MTH7101",
        "Functional Analysis",
    ),
    (
        "Faculty of Science",
        "MTH7102",
        "Model Theory",
    ),
    (
        "Faculty of Science",
        "MTH7103",
        "Dynamical Systems",
    ),
    (
        "Faculty of Science",
        "MTH7104",
        "Numerial Analysis",
    ),
    (
        "Faculty of Science",
        "MTH7105",
        "Computational and Research Methods",
    ),
    (
        "Faculty of Science",
        "MTH7107",
        "Combinatorial Design Theory",
    ),
    (
        "Faculty of Science",
        "PHY1101",
        "Introduction to Physics Practical",
    ),
    (
        "Faculty of Science",
        "PHY1102",
        "Mathematical Physics",
    ),
    (
        "Faculty of Science",
        "PHY1103",
        "Classical Mechanics I",
    ),
    (
        "Faculty of Science",
        "PHY1104",
        "Properties of Matter THEORY",
    ),
    (
        "Faculty of Science",
        "PHY1105",
        "Heat and Thermodynamics",
    ),
    (
        "Faculty of Science",
        "PHY2101",
        "Practical Physics I",
    ),
    (
        "Faculty of Science",
        "PHY2102",
        "Mathematical Physics",
    ),
    (
        "Faculty of Science",
        "PHY2103",
        "Classical Mechanics II",
    ),
    (
        "Faculty of Science",
        "PHY2104",
        "Solid State Physics I",
    ),
    (
        "Faculty of Science",
        "PHY2107",
        "Electromagnetism I",
    ),
    (
        "Faculty of Science",
        "PHY3101",
        "Physics Practical III",
    ),
    (
        "Faculty of Science",
        "PHY3103",
        "Classical Mechanics III",
    ),
    (
        "Faculty of Science",
        "PHY3104",
        "Solid State Physics II",
    ),
    (
        "Faculty of Science",
        "PHY3108",
        "Electronics II",
    ),
    (
        "Faculty of Science",
        "PHY3109",
        "Stellar Stracture and Evolution",
    ),
    (
        "Faculty of Science",
        "PHY3111",
        "Computational Physics II",
    ),
    (
        "Faculty of Science",
        "PHY3112",
        "Communication Systems and Instrumentation",
    ),
    (
        "Faculty of Science",
        "PHY3114",
        "Introduction to Space Physics and Technology",
    ),
    ("Faculty of Applied Sciences and Technology", "BCE2104", "Signals and Systems"),
    (
        "Faculty of Applied Sciences and Technology",
        "BCE2106",
        "Fundamentals of Fluid Mechanics",
    ),
    ("Faculty of Applied Sciences and Technology", "BCE2108", "Engineering Economics"),
    ("Faculty of Applied Sciences and Technology", "BCE2110", "Thermofluids"),
    ("Faculty of Applied Sciences and Technology", "BME2106", "Physiology"),
    ("Faculty of Applied Sciences and Technology", "BME2107", "Pharmacology"),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE2107",
        "Engineering Surveying II",
    ),
    (
        "Faculty of Applied Sciences and Technology",
        "CVE2108",
        "Theory of Structures II",
    ),
    ("Faculty of Applied Sciences and Technology", "CVE2109", "Construction Materials"),
    ("Faculty of Applied Sciences and Technology", "CVE2110", "Hydrology II"),
    ("Faculty of Applied Sciences and Technology", "EEE2105", "Power Electronics"),
    ("Faculty of Applied Sciences and Technology", "EEE2108", "Digital Systems"),
    ("Faculty of Applied Sciences and Technology", "EEE2110", "Electromagnetic Fields"),
    ("Faculty of Health Sciences", "BME2113", "Clinical Skills"),
    ("Faculty of Health Sciences", "BME2114", "Patient Assessment"),
    ("Faculty of Health Sciences", "BME3114", "Pathophysiology"),
    ("Faculty of Health Sciences", "BME3115", "Pharmacology II"),
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
    subjects = {
        row.name: row
        for row in (
            await db.execute(select(Subject).where(Subject.university_id.is_(None)))
        ).scalars()
    }
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
        import re as _re

        _m = _re.search(r"[A-Za-z]+(\d)(\d)", code or "")
        db.add(
            CourseUnit(
                code=code,
                name=name,
                university_id=university.id,
                subject_id=subject.id if subject is not None else None,
                grade_id=None,
                year_level=int(_m.group(1)) if _m and int(_m.group(1)) < 7 else None,
                semester=int(_m.group(2)) if _m else None,
            )
        )
        added += 1
    await db.flush()
    return added, sorted(orphans)


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

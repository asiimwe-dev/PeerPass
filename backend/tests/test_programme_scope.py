"""The programme shelf inside a faculty, asserted at every surface.

A faculty publishes one catalogue, but its programmes publish different courses
under different codes. The faculty is the boundary; the programme is the shelf.
Someone reading Information Technology must not be offered Computer Science's
units by the catalogue, must not be able to declare one as a primary module, ask
for help in one, match against one, or prove competence in one. Discovery has to
agree: a tutor enrolled in another programme is not somebody this student can ask
for help, because every unit that tutor is verified in is off this student's
shelf.

Two programmes of one faculty is the whole setup. A second *faculty* would only
re-test the wider boundary that `test_faculty_scope.py` already covers.

Null is load-bearing on both sides and each null means something different:

- a unit with no programme is the faculty-wide shelf, visible to every programme;
- an account with no programme predates the field, or belongs to a faculty whose
  programmes are not loaded, and sees the whole faculty rather than nothing.

Both are asserted here, because a rule that reads null as "mismatch" would lock
either state out of a catalogue it has every right to.
"""

from decimal import Decimal

import pytest
from sqlalchemy import select

from app.models.competency import Competency
from app.models.course_unit import CourseUnit, Program, Subject, University
from app.models.enums import (
    CompetencyStatus,
    TutorStanding,
    UserRole,
    VerificationSource,
)
from app.models.grading_scale import Grade
from app.models.tutor_profile import TutorProfile
from app.models.user import User, set_roles
from tests.conftest import CommittedEnv
from tests.support import bearer, register

UNITS_URL = "/v1/academics/course-units"
PROGRAMS_URL = "/v1/academics/programs"

FACULTY = "Faculty of Computing and Informatics"
SIBLING_FACULTY = "Faculty of Science"
INFORMATION_TECHNOLOGY = "Information Technology"
COMPUTER_SCIENCE = "Computer Science"

#: A unit every programme in the faculty takes. Staged rather than taken from the
#: seed: the shipped FCI catalogue happens to be entirely programme-owned, but
#: the faculty-wide shelf is a supported state and the only way to assert it.
FACULTY_WIDE_CODE = "FCI1000"

BIT_UNIT_CODE = "BIT1101"
CSC_UNIT_CODE = "CSC1101"


@pytest.fixture
async def catalogue(committed_env: CommittedEnv) -> dict:
    """The seeded faculty, its programmes, and one unit from each shelf."""
    async with committed_env.session() as session:
        university = await session.scalar(select(University))
        assert university is not None, "the seed must publish a university"
        faculty = await session.scalar(select(Subject).where(Subject.name == FACULTY))
        assert faculty is not None, "the seed must publish the FCI faculty"

        programs = {
            program.name: program
            for program in (
                await session.execute(
                    select(Program).where(Program.university_id == university.id)
                )
            ).scalars()
        }
        bit = programs[INFORMATION_TECHNOLOGY]
        csc = programs[COMPUTER_SCIENCE]

        wide = CourseUnit(
            code=FACULTY_WIDE_CODE,
            name="Faculty-wide unit",
            university_id=university.id,
            subject_id=faculty.id,
        )
        session.add(wide)

        sibling_faculty = Subject(name=SIBLING_FACULTY, university_id=university.id)
        session.add(sibling_faculty)
        await session.flush()
        sibling_program = Program(
            name="Science",
            level="undergraduate",
            university_id=university.id,
            faculty_id=sibling_faculty.id,
        )
        session.add(sibling_program)
        await session.flush()

        units = (await session.execute(select(CourseUnit))).scalars().all()
        by_code = {unit.code: unit for unit in units}
        grade = (
            (await session.execute(select(Grade).where(Grade.label == "A").limit(1)))
            .scalars()
            .first()
        )
        assert grade is not None, "the seed must publish a passing grade"
        await session.commit()

        return {
            "university_id": university.public_id,
            "faculty_id": faculty.public_id,
            "sibling_faculty_id": sibling_faculty.public_id,
            "bit_programme_id": bit.public_id,
            "csc_programme_id": csc.public_id,
            "sibling_programme_id": sibling_program.public_id,
            "bit_codes": {unit.code for unit in units if unit.program_id == bit.id},
            "csc_codes": {unit.code for unit in units if unit.program_id == csc.id},
            "bit_unit": by_code[BIT_UNIT_CODE],
            "csc_unit": by_code[CSC_UNIT_CODE],
            "wide_unit": wide,
            "grade": grade,
        }


async def _in_programme(
    env: CommittedEnv,
    catalogue: dict,
    programme_id,
    email: str,
    *,
    roles: set[UserRole] | None = None,
) -> tuple[dict, User]:
    """A registered account placed on `programme_id`'s shelf, by the user's route.

    `PATCH /v1/users/me` rather than a column write: choosing a programme is the
    wizard's academic step, and a test about the shelf should not be the one
    place that skips it. `programme_id=None` stages the account that predates
    the field -- the faculty-wide state.
    """
    client = env.client
    body = await register(client, email)
    payload: dict = {
        "university_id": str(catalogue["university_id"]),
        "faculty_id": str(catalogue["faculty_id"]),
        "academic_data_consented": True,
    }
    if programme_id is not None:
        payload["program_id"] = str(programme_id)

    response = await client.patch("/v1/users/me", headers=bearer(body), json=payload)
    assert response.status_code == 200, response.text

    async with env.session() as session:
        user = await session.scalar(select(User).where(User.email == email))
        assert user is not None
        if roles:
            await set_roles(session, user.id, roles)
            await session.commit()
        return body, user


async def _verified_tutor_in(
    env: CommittedEnv,
    catalogue: dict,
    *,
    programme_id,
    unit: CourseUnit,
    email: str,
) -> User:
    """A tutor on `programme_id`'s shelf with a verified competency in `unit`.

    The competency is written directly rather than claimed through the API
    because a cross-programme claim is exactly what the API refuses. That refusal
    is tested elsewhere in this module; here the row is the legacy state it is
    meant to leave behind, and matching has to refuse it a second time.
    """
    _body, tutor = await _in_programme(
        env,
        catalogue,
        programme_id,
        email,
        roles={UserRole.STUDENT, UserRole.TUTOR},
    )
    async with env.session() as session:
        session.add(
            TutorProfile(
                user_id=tutor.id,
                standing=TutorStanding.VERIFIED,
                completed_sessions=4,
                rating_total=Decimal("19.00"),
                rating_count=4,
            )
        )
        session.add(
            Competency(
                user_id=tutor.id,
                course_unit_id=unit.id,
                grade_id=catalogue["grade"].id,
                status=CompetencyStatus.VERIFIED,
                source=VerificationSource.TRANSCRIPT,
            )
        )
        await session.commit()
    return tutor


def _codes(response) -> set[str]:
    assert response.status_code == 200, response.text
    return {unit["code"] for unit in response.json()}


# --- the catalogue ---------------------------------------------------------


async def test_the_catalogue_offers_only_your_own_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A BIT student is offered the BIT shelf and the faculty-wide units.

    Not "the client hides the rest": the endpoint returns nothing from a sibling
    programme, so a client that forgot to filter would still be correct.
    """
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.catalogue@must.ac.ug",
    )

    response = await committed_env.client.get(UNITS_URL, headers=bearer(body))

    codes = _codes(response)
    assert codes == catalogue["bit_codes"] | {FACULTY_WIDE_CODE}
    assert not (codes & catalogue["csc_codes"])


async def test_a_faculty_wide_unit_is_on_every_programme_shelf(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A unit with no programme belongs to the faculty, not to one degree.

    The null is a meaning, not a gap: a course every programme takes has to stay
    visible to all of them, or moving it out of one degree silently removes it
    from the others.
    """
    bit, _ = await _in_programme(
        committed_env, catalogue, catalogue["bit_programme_id"], "wide.bit@must.ac.ug"
    )
    csc, _ = await _in_programme(
        committed_env, catalogue, catalogue["csc_programme_id"], "wide.csc@must.ac.ug"
    )

    for body in (bit, csc):
        units = (await committed_env.client.get(UNITS_URL, headers=bearer(body))).json()
        wide = next(unit for unit in units if unit["code"] == FACULTY_WIDE_CODE)
        assert wide["program_id"] is None


async def test_an_account_without_a_programme_sees_the_whole_faculty(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """The compatibility state stays usable.

    An account that predates programmes, or one whose faculty has not published
    its programmes yet, must not be shown an empty catalogue: that would lock it
    out of the product. It sees the faculty, which is the behaviour it had before
    programmes existed.
    """
    body, _ = await _in_programme(
        committed_env, catalogue, None, "legacy.account@must.ac.ug"
    )

    codes = _codes(await committed_env.client.get(UNITS_URL, headers=bearer(body)))

    assert catalogue["bit_codes"] <= codes
    assert catalogue["csc_codes"] <= codes
    assert FACULTY_WIDE_CODE in codes


async def test_every_seeded_unit_names_the_programme_that_publishes_it(
    committed_env: CommittedEnv,
) -> None:
    """A seeded row without a programme would leak into every programme's shelf.

    That is not a cosmetic missing value: it makes the whole catalogue visible to
    every student in the faculty, which looks like the shelf rule silently
    failing. The seeder reports it as a warning; this asserts it did not happen.
    """
    async with committed_env.session() as session:
        unassigned = (
            (
                await session.execute(
                    select(CourseUnit.code).where(
                        CourseUnit.program_id.is_(None),
                        CourseUnit.subject_id.is_not(None),
                    )
                )
            )
            .scalars()
            .all()
        )

    assert list(unassigned) == []


async def test_the_programmes_endpoint_narrows_to_one_faculty(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """What the wizard calls after the student picks a faculty.

    A faculty filter is not authorisation -- the catalogue is public -- but the
    picker must not be handed another faculty's degrees when it asked for this
    one's.
    """
    response = await committed_env.client.get(
        PROGRAMS_URL,
        params={
            "university_id": str(catalogue["university_id"]),
            "faculty_id": str(catalogue["faculty_id"]),
        },
    )

    assert response.status_code == 200, response.text
    programs = response.json()
    names = {program["name"] for program in programs}
    # Every programme of the faculty, and nothing from the sibling faculty the
    # fixture stages. Naming the two the rest of this module uses keeps the test
    # about the filter rather than about how many degrees MUST happens to offer.
    assert {INFORMATION_TECHNOLOGY, COMPUTER_SCIENCE} <= names
    assert "Science" not in names
    assert all(
        program["faculty_id"] == str(catalogue["faculty_id"]) for program in programs
    )


# --- acting on a course ----------------------------------------------------


async def test_a_primary_module_cannot_be_chosen_from_a_sibling_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A profile must not list a course its owner's shelf does not publish.

    Primary modules seed matching, so accepting one would put a course on the
    profile that every other endpoint then refuses -- the profile becoming the
    single place the shelf did not hold.
    """
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.primary@must.ac.ug",
    )

    response = await committed_env.client.patch(
        "/v1/users/me",
        headers=bearer(body),
        json={"primary_course_unit_ids": [str(catalogue["csc_unit"].public_id)]},
    )

    assert response.status_code == 422, response.text
    assert "programme" in response.json()["detail"].lower()


async def test_a_help_request_cannot_be_raised_against_a_sibling_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """The first write that names a course refuses a sibling shelf."""
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.requester@must.ac.ug",
    )

    response = await committed_env.client.post(
        "/v1/matching/help-requests",
        headers=bearer(body),
        json={
            "course_unit_id": str(catalogue["csc_unit"].public_id),
            "topic": "recursion",
        },
    )

    assert response.status_code == 422, response.text
    assert "programme" in response.json()["detail"].lower()


async def test_matching_cannot_be_asked_about_a_sibling_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """And the read that answers it, with the shelf named."""
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.matcher@must.ac.ug",
    )

    response = await committed_env.client.post(
        "/v1/matching/suggestions",
        headers=bearer(body),
        json={"course_unit_id": str(catalogue["csc_unit"].public_id)},
    )

    assert response.status_code == 422, response.text
    assert "programme" in response.json()["detail"].lower()


async def test_a_tutor_cannot_apply_against_a_sibling_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """Verification starts the rule: a claim on another shelf is refused."""
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.applicant@must.ac.ug",
    )

    response = await committed_env.client.post(
        "/v1/competencies",
        headers=bearer(body),
        json={
            "course_unit_id": str(catalogue["csc_unit"].public_id),
            "grade_id": str(catalogue["grade"].public_id),
            "source": "transcript",
        },
    )

    assert response.status_code == 422, response.text
    assert "programme" in response.json()["detail"].lower()


# --- changing programmes ---------------------------------------------------


async def test_changing_programme_keeps_only_the_modules_the_new_shelf_offers(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A programme move inside a faculty is not a faculty move.

    Dropping every module would be simpler and wrong: a BIT student moving to CSC
    keeps the faculty-wide units they had, and only the BIT-only ones go. Silence
    here would leave the profile claiming courses the account can no longer act
    on.
    """
    body, _ = await _in_programme(
        committed_env, catalogue, catalogue["bit_programme_id"], "bit.mover@must.ac.ug"
    )
    declared = await committed_env.client.patch(
        "/v1/users/me",
        headers=bearer(body),
        json={
            "primary_course_unit_ids": [
                str(catalogue["bit_unit"].public_id),
                str(catalogue["wide_unit"].public_id),
            ]
        },
    )
    assert declared.status_code == 200, declared.text

    moved = await committed_env.client.patch(
        "/v1/users/me",
        headers=bearer(body),
        json={"program_id": str(catalogue["csc_programme_id"])},
    )

    assert moved.status_code == 200, moved.text
    profile = moved.json()
    assert profile["program_id"] == str(catalogue["csc_programme_id"])
    assert profile["program_name"] == COMPUTER_SCIENCE
    assert profile["primary_course_unit_ids"] == [str(catalogue["wide_unit"].public_id)]


async def test_changing_faculty_clears_the_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A programme belongs to a faculty, so it cannot outlive the move.

    The faculty change is a boundary move; keeping the programme would leave an
    account pointing at a degree in a faculty it is no longer in.
    """
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.to.science@must.ac.ug",
    )

    moved = await committed_env.client.patch(
        "/v1/users/me",
        headers=bearer(body),
        json={"faculty_id": str(catalogue["sibling_faculty_id"])},
    )

    assert moved.status_code == 200, moved.text
    assert moved.json()["faculty_id"] == str(catalogue["sibling_faculty_id"])
    assert moved.json()["program_id"] is None


async def test_a_programme_from_another_faculty_cannot_be_chosen(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """The programme is validated against the faculty being set."""
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["bit_programme_id"],
        "bit.foreign.degree@must.ac.ug",
    )

    response = await committed_env.client.patch(
        "/v1/users/me",
        headers=bearer(body),
        json={"program_id": str(catalogue["sibling_programme_id"])},
    )

    assert response.status_code == 422, response.text
    assert "programme" in response.json()["detail"].lower()


# --- discovery -------------------------------------------------------------


async def test_matching_excludes_a_tutor_from_another_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A legacy competency across the shelf is not a licence to be matched.

    The claim endpoint refuses a cross-programme competency now, but a row
    written before that rule existed can still sit in the database. Matching it
    would quietly undo the rule. A tutor with no programme is the bridge and stays
    proposal-worthy, which is asserted alongside so the exclusion is not the
    query excluding everyone.
    """
    from_bit = await _verified_tutor_in(
        committed_env,
        catalogue,
        programme_id=catalogue["bit_programme_id"],
        unit=catalogue["csc_unit"],
        email="bit.tutor.csc.unit@must.ac.ug",
    )
    bridge = await _verified_tutor_in(
        committed_env,
        catalogue,
        programme_id=None,
        unit=catalogue["csc_unit"],
        email="bridge.tutor.csc.unit@must.ac.ug",
    )
    student, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["csc_programme_id"],
        "csc.matcher@must.ac.ug",
    )

    response = await committed_env.client.post(
        "/v1/matching/suggestions",
        headers=bearer(student),
        json={"course_unit_id": str(catalogue["csc_unit"].public_id)},
    )

    assert response.status_code == 200, response.text
    candidates = [item["tutor"]["user_id"] for item in response.json()["candidates"]]
    assert candidates == [str(bridge.public_id)]
    assert str(from_bit.public_id) not in candidates


async def test_the_rail_excludes_a_tutor_from_another_programme(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """Discovery agrees with matching, one level in from the faculty.

    A tutor on another programme's shelf is only verified in units this student
    cannot ask about, so listing them offers a conversation with no course in it.
    The no-programme tutor remains, for the same bridge reason as matching.
    """
    from_bit = await _verified_tutor_in(
        committed_env,
        catalogue,
        programme_id=catalogue["bit_programme_id"],
        unit=catalogue["csc_unit"],
        email="bit.tutor.rail@must.ac.ug",
    )
    bridge = await _verified_tutor_in(
        committed_env,
        catalogue,
        programme_id=None,
        unit=catalogue["csc_unit"],
        email="bridge.tutor.rail@must.ac.ug",
    )
    student, _ = await _in_programme(
        committed_env, catalogue, catalogue["csc_programme_id"], "csc.rail@must.ac.ug"
    )

    response = await committed_env.client.get("/v1/tutors/top", headers=bearer(student))

    assert response.status_code == 200, response.text
    listed = [entry["user_id"] for entry in response.json()]
    assert str(bridge.public_id) in listed
    assert str(from_bit.public_id) not in listed


async def test_the_rail_for_a_sibling_programme_unit_is_empty(
    committed_env: CommittedEnv, catalogue: dict
) -> None:
    """A stale picker value yields an empty rail, never a 4xx.

    Same contract as a unit from another faculty: the client asked about a unit
    it believed was for it, and "no tutors" is the honest answer. A refusal would
    put the discovery screen into an error state over a value the student cannot
    fix from there.
    """
    body, _ = await _in_programme(
        committed_env,
        catalogue,
        catalogue["csc_programme_id"],
        "csc.rail.filter@must.ac.ug",
    )
    await _verified_tutor_in(
        committed_env,
        catalogue,
        programme_id=None,
        unit=catalogue["bit_unit"],
        email="bridge.tutor.bit.unit@must.ac.ug",
    )

    response = await committed_env.client.get(
        "/v1/tutors/top",
        headers=bearer(body),
        params={"course_unit_id": str(catalogue["bit_unit"].public_id)},
    )

    assert response.status_code == 200, response.text
    assert response.json() == []

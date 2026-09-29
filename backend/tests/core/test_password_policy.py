"""The password acceptance policy."""

import pytest

from app.core.password_policy import (
    MAX_PASSWORD_LENGTH,
    MIN_PASSWORD_LENGTH,
    denial_reason,
)

# A long passphrase with no deny-listed substring and no trailing digits, so a
# test that expects acceptance is only ever measuring the rule it means to.
_A_GOOD_PASSWORD = "correct horse battery staple"


def test_a_long_passphrase_is_accepted() -> None:
    assert denial_reason(_A_GOOD_PASSWORD) is None


# --- Length ------------------------------------------------------------------


def test_s1_the_minimum_is_twelve() -> None:
    """Length beats composition rules.

    A required-symbol rule produces `Passw0rd!`, which is predictable and is
    spelled out in every credential corpus. Length has no equivalent failure
    mode, so the minimum is set well above the service average and there is no
    symbol requirement at all.
    """
    assert MIN_PASSWORD_LENGTH == 12


def test_a_password_one_below_the_minimum_is_refused() -> None:
    assert denial_reason("a" * (MIN_PASSWORD_LENGTH - 1)) is not None


def test_a_password_exactly_at_the_minimum_is_accepted() -> None:
    """The boundary itself, not just either side of it.

    A student who types a twelve character passphrase has to be let through;
    an off-by-one here is the kind of defect that only shows up in production
    sign-up, and only for the people unlucky enough to pick the exact length.
    """
    assert denial_reason("a" * MIN_PASSWORD_LENGTH) is None


def test_a_password_one_above_the_maximum_is_refused() -> None:
    assert denial_reason("a" * (MAX_PASSWORD_LENGTH + 1)) is not None


def test_a_password_exactly_at_the_maximum_is_accepted() -> None:
    assert denial_reason("a" * MAX_PASSWORD_LENGTH) is None


def test_the_maximum_is_128() -> None:
    """Bcrypt truncates at 72 bytes silently.

    The bound is here so that a future move to bcrypt cannot quietly reduce a
    128 character password to its first 72 with no error to warn anyone.
    """
    assert MAX_PASSWORD_LENGTH == 128


# --- The deny-list -----------------------------------------------------------


@pytest.mark.parametrize(
    "password",
    [
        "password1234",
        "Password1234",
        "PASSWORD1234",
        "qwerty123456",
        "letmein12345",
    ],
)
def test_s1_a_common_password_is_refused_whatever_its_case(password: str) -> None:
    """ "password", "Password" and "PASSWORD" are one password to an attacker."""
    assert denial_reason(password) is not None


@pytest.mark.parametrize(
    "password",
    [
        "password1234!",
        "password1234.",
        "password1234 ",
        "password1234_",
    ],
)
def test_s1_trailing_decoration_does_not_rescue_a_denied_password(
    password: str,
) -> None:
    """The realistic bypass, and the reason stripping is part of the rule.

    An attacker who tries a breach list tries the obvious transformations of
    each entry, so a deny-list that only matches literals stops at exactly the
    passwords that are actually tried.
    """
    assert denial_reason(password) is not None


@pytest.mark.parametrize("password", ["peerpass1234", "PeerPass12345", "peerpassapp1"])
def test_s1_the_service_name_is_refused(password: str) -> None:
    """A student who types the product name has not protected a secret.

    The service name is the first thing any credential-stuffing list tries for
    this site, so allowing it would be allowing a password that is already
    public.
    """
    assert denial_reason(password) is not None


# --- What the policy deliberately does not block ----------------------------


@pytest.mark.parametrize(
    "password",
    [
        # A real Ugandan surname followed by a digit. The trailing strip reduces
        # this to "makwanasaprofessor", which is not on the list, so a genuine
        # name that happens to appear in some breach corpus is not blocked.
        "makwanasaprofessor1",
        # A passphrase with no dictionary words at all.
        "xq7vbn2mkl9p",
        # Emoji and non-Latin scripts must not be charset-policed. Twelve of
        # them, because the minimum is twelve code points and a `str` counts one
        # per character regardless of how many bytes UTF-8 needs.
        "🔐🔐🔐🔐🔐🔐🔐🔐🔐🔐🔐🔐",
        "manzimu-kimutano2024",
    ],
)
def test_s1_a_password_the_policy_does_not_recognise_is_accepted(
    password: str,
) -> None:
    """The rule is a deny-list, and this is what that buys.

    A deny-list cannot exhaust the passwords a determined attacker will try, so
    it is not the thing making passwords safe -- Argon2's cost per guess is.
    Its job is to catch the small number of choices that would otherwise make
    that cost affordable, without rejecting real people. These are the cases a
    composition rule or an aggressive blocklist would get wrong, and the cost of
    getting them wrong is a student who cannot register.
    """
    assert denial_reason(password) is None


def test_s1_an_empty_password_is_refused() -> None:
    assert denial_reason("") is not None

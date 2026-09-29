"""Password acceptance policy.

Separate from `app.core.security`, which answers "how does this password become
a stored hash". This module answers the question that comes first: "should this
password be allowed to exist at all?".

Checked at registration and at password change. Never at sign-in. That
distinction is the whole point: a student who chose a password that later lands
on a breach list can still get into their own account, because denying them at
sign-in would let anyone lock them out by reporting their password as common.
Refusing it at *creation* is the only place where a deny-list is safe.

The policy is length-based with no composition rules. Length is the property
that actually resists offline cracking, and character-class requirements are
well documented to produce `Passw0rd!` -- a predictable substitution that meets
the rule while being weaker than a passphrase of the same length. See
`docs/architecture.md` section 9.
"""

#: Both bounds are counted in Unicode code points, which is what `len()` returns
#: for a `str` and therefore what the schema's `min_length`/`max_length` count
#: too. The two have to agree: if the policy counted bytes and the schema counted
#: code points, an eight character non-ASCII password would pass one and fail the
#: other, and the rejection would arrive as an opaque field error from a
#: different layer than the one that explains it.
#:
#: Eight, not the twelve this was originally set to. The length floor exists to
#: spare a student from being asked to invent a long passphrase, and twelve was
#: measurably past the point where students start writing `Password123!` and
#: forgetting it -- the predictable substitution is worse than a shorter
#: memorable secret. What keeps an eight character password safe is not the floor
#: but the deny-list below, which rejects the passwords an attacker actually
#: opens with, and Argon2id at 19 MiB, which makes each guess expensive. A
#: longer floor only ever rejected honest students, not attackers: nobody
#: brute-forces at twelve when the useful guesses are all short.
#:
#: The residual risk is recorded rather than hidden. There is still no rate
#: limiting on sign-in (see `docs/architecture.md` 9.8), so the number of guesses
#: is unbounded and the deny-list is the only thing standing between a leaked
#: address and a guessed password. Rate limiting is the correct follow-up and is
#: the next thing to add here.
MIN_PASSWORD_LENGTH = 8
MAX_PASSWORD_LENGTH = 128

#: Returned by `denial_reason` when the password is on the deny-list.
_DENIED_MESSAGE = (
    "That password is too common. Choose something longer that is not a "
    "dictionary word or a keyboard pattern."
)

#: The product's own name, plus the obvious variants. A password that names the
#: service it authenticates to is the first thing any credential-stuffing list
#: tries, and a student who types "peerpass" is not protecting a secret.
_BRAND_DENY = frozenset({"peerpass", "peerpassapp", "peerpasslogin"})

#: The most-used passwords worldwide, which is also the list a credential-
#: stuffing run opens with. Deliberately static.
#:
#: The alternative is a live breach-API lookup, which this project does not do
#: for two reasons: it would hand a third party a list of student email
#: addresses to check, and it would make account creation depend on somebody
#: else's uptime. The cost of the static approach is that the list goes stale,
#: so it needs a manual refresh when either the incident rate warrants it or
#: this file is two years old. The list is intentionally kept small and
#: readable rather than exhaustive, because an unreadable deny-list is one
#: nobody reviews. The `noqa` below is for SIM905, which would expand this into
#: a hundred lines of quoted entries: worse to read and worse to diff, and the
#: whole point of keeping the list short enough to audit by eye is lost.
_COMMON_PASSWORDS = frozenset(
    """
    123456 password 123456789 12345678 12345 111111 1234567 sunshine
    qwerty iloveyou princess 123123 1234 000000 123321 qwerty123 1q2w3e4r
    654321 dontyouknow 123qwe zaq12wsx dragon 121212 baseball abc123 football
    monkey letmein 696969 shadow master 666666 qwertyuiop 123321 mustang
    michael qwerty1 7777777 121212 1234567890 qwerty1 starwars dragon1
    trustno1 1234 iloveyou baseball1 whatever 1qaz2wsx hunter2 6543 pass
    flower hello 000000 master1 qwerty12 test test1 passw0rd welcome
    shadow1 dragon123 welcome1 password1 princess1 123abc 1111 aa123456
    123654 123abc456 123456a a123456 1234abcd 12121212 qwertyuiop1
    computer batman superman 1q2w3e 12345abc asdfgh asdfghjkl 123qweasd
    1qazxsw2 qweasdzxc zaq1xsw2 1q2w3e4r5t password1 administrator
    letmein1 sunshine1 iloveyou1 monkey1 shadow1 master1 dragon1
    qwerty1 1234qwer q1w2e3r4 1234abcd1 asdzxc qwerty12345 1q2w3e4r5t6y
    zxcvbnm 987654321 qwerty2020 summer2020 winter2020 password2020
    student teacher welcome123 changeme changeme123 default secret
    server qwerty12345 1q2w3e4r 12345678a
    abcdefgh abcdefghi a1b2c3d4 qazwsxedc 1q2w3e4r5t6y7u
    asshole dickhead
    """.split()  # noqa: SIM905
)


#: Characters stripped from the trailing end of a password before the deny-list
#: lookup, and nothing else. Not a normalisation step: the submitted password is
#: hashed exactly as given, so this only affects whether a known-bad password is
#: recognised through one of its common decorations.
_TRAILING_NOISE = "0123456789!@#$%^&*()-_=+.,;:?/\\|~` \t"


def denial_reason(password: str) -> str | None:
    """Why this password is unacceptable, or `None` when it is acceptable.

    Both length bounds are enforced here as well as in the schema, so a caller
    validating outside a schema gets the same answer. The schema raises them as
    field-level errors in the usual shape; this returns a reason string. The
    bounds themselves are owned by this module, and the schema imports them, so
    there is one number to change.

    The rule the schema cannot express is a set membership test. Matching is
    case-insensitive, and a trailing run of digits or punctuation is stripped
    before the lookup. "password", "Password", "password1" and "password!" are
    the same password to an attacker, and checking only the literal string would
    let three of the four through. The strip is deliberately only applied to the
    *trailing* end: "makwanasaprofessor1" normalises to "makwanasaprofessor",
    which is not on the list, so a real Ugandan surname that happens to appear in
    a breach corpus is not blocked by accident.
    """
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Password must be at least {MIN_PASSWORD_LENGTH} characters long."

    if len(password) > MAX_PASSWORD_LENGTH:
        # Argon2 hashes a password of any length, so there is no technical reason
        # to stop at 128. The bound is here because bcrypt truncates at 72 bytes
        # silently, and a future switch to it would make the first 72 characters
        # the entire password with no error to warn anyone. Refusing to store the
        # ambiguous case now is cheaper than discovering it later.
        return f"Password must be at most {MAX_PASSWORD_LENGTH} characters long."

    candidate = password.casefold()
    if candidate in _COMMON_PASSWORDS or candidate in _BRAND_DENY:
        return _DENIED_MESSAGE

    # Every character an attacker's mutation list tends to append, and only at the
    # trailing end. Whitespace is in here because a trailing space is one of the
    # most common variations actually tried -- `password ` and `password1` are
    # guesses that reach a real login form constantly, and browsers silently
    # discard them from a password field, so a student really does type one by
    # accident. This affects the lookup only: the password that gets hashed is
    # the one that was submitted, unstripped.
    stripped = candidate.rstrip(_TRAILING_NOISE)
    if stripped and stripped in _COMMON_PASSWORDS:
        return _DENIED_MESSAGE
    if stripped in _BRAND_DENY:
        return _DENIED_MESSAGE

    return None

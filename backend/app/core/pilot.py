"""Facts that describe the pilot institution.

The seed writes this institution and the public university list filters to it.
Keeping one definition is the point: two literals would drift the day one is
corrected, and the symptom would be an empty list on the sign-up screen -- not
an error anyone could trace back to a typo in a route module.

The list filters by name because the pilot row's `public_id` is generated when
the seed runs and is therefore not a compile-time constant. A deployment that
renames the institution must update this one value, which is why the seed and
the route both read it from here.
"""

PILOT_UNIVERSITY_NAME = "Mbarara University of Science and Technology"

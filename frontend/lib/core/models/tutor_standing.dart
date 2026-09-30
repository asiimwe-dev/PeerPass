/// A tutor's standing with the platform.
///
/// Not the same thing as holding the tutor role: the role is a fact about the
/// account, while standing is a judgement about performance that the API
/// changes over time. `probationary` is where every tutor starts; `verified` is
/// earned by the API's own thresholds.
///
/// Whether a given standing makes a tutor eligible for a unit is a matching
/// rule and lives in the API. This enum only says how the standing is
/// *displayed*, so a state added after this release shows up as unfamiliar
/// instead of crashing a rail the student is looking at.
enum TutorStanding {
  probationary('probationary'),
  verified('verified'),
  reduced('reduced'),
  suspended('suspended');

  TutorStanding(this.wireValue);

  /// The value the API uses on the wire.
  ///
  /// Held separately from [name] for the reason `UserRole` holds it separately:
  /// renaming the Dart identifier must not change what the client reads.
  final String wireValue;

  /// How the standing is labelled to a student.
  ///
  /// A word rather than the wire value: `probationary` is a term the API uses,
  /// and a student reads "Probationary" on a chip without having to learn the
  /// vocabulary first.
  String get label => switch (this) {
    probationary => 'Probationary',
    verified => 'Verified',
    reduced => 'Reduced',
    suspended => 'Suspended',
  };

  /// The standing parsed from a wire value, or null when unrecognised.
  ///
  /// Null rather than a throw, on the same grounds as `UserRole.fromWire`: an
  /// unfamiliar standing is rendered verbatim next to the ones we know.
  static TutorStanding? fromWire(String? value) {
    for (final standing in TutorStanding.values) {
      if (standing.wireValue == value) return standing;
    }
    return null;
  }
}

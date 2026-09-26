/// The roles a person can hold on the platform.
///
/// A single user may hold more than one, which is why the API models this as a
/// join table rather than a column on the user row. Deciding which actions a
/// role unlocks is a backend concern; the client only needs to know which role
/// to present.
enum UserRole {
  student('student'),
  tutor('tutor');

  UserRole(this.wireValue);

  /// The value the API uses on the wire.
  ///
  /// Snake case to match the documented wire format, kept separate from
  /// [name] so renaming the Dart identifier cannot silently change the payload.
  final String wireValue;

  /// The role parsed from a wire value, or null when unrecognised.
  ///
  /// Null rather than a throw: a role the client does not know about is
  /// something to render as an unrecognised role, not something to crash on.
  /// Forward compatibility matters while the pilot is adding roles.
  static UserRole? fromWire(String? value) {
    for (final role in UserRole.values) {
      if (role.wireValue == value) return role;
    }
    return null;
  }
}

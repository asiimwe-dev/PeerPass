import 'package:flutter/foundation.dart';
import 'package:ulearn/core/models/user_role.dart';

/// An authenticated identity restored from stored tokens.
///
/// Deliberately narrow: it holds what the router needs to decide where to send
/// someone. The full profile, with name, university, and academic record, is
/// owned by the profile feature.
@immutable
class AuthSession {
  const AuthSession({
    required this.publicId,
    required this.email,
    required this.roles,
  });

  final String publicId;

  final String email;

  /// Every role the person holds.
  ///
  /// A set rather than a single value because a tutor is also a student, and
  /// the client renders the tutor surfaces for them.
  final Set<UserRole> roles;

  bool hasRole(UserRole role) => roles.contains(role);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession &&
          other.publicId == publicId &&
          other.email == email &&
          setEquals(other.roles, roles);

  @override
  int get hashCode =>
      Object.hash(publicId, email, Object.hashAllUnordered(roles));

  @override
  String toString() => 'AuthSession($publicId, $email, $roles)';
}

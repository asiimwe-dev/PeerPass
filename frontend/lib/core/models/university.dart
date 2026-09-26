import 'package:flutter/foundation.dart';
import 'package:ulearn/core/models/grading_scale.dart';

/// A university that students and tutors belong to.
///
/// Used by sign-up, tutor registration, and matching, so it lives in `core/`
/// rather than in any single feature.
@immutable
class University {
  const University({
    required this.publicId,
    required this.name,
    required this.gradingScale,
  });

  /// Opaque identifier, safe to put in a URL.
  ///
  /// The client never sees the database's primary key, so a leaked reference
  /// cannot be used to enumerate other tables.
  final String publicId;

  final String name;

  /// The scale this university grades on.
  ///
  /// Required rather than optional because the competency rule is expressed in
  /// terms of a university's own scale, and a tutor record without one could
  /// not be evaluated against it.
  final GradingScale gradingScale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is University &&
          other.publicId == publicId &&
          other.name == name &&
          other.gradingScale == gradingScale;

  @override
  int get hashCode => Object.hash(publicId, name, gradingScale);

  @override
  String toString() => 'University($publicId, $name)';
}

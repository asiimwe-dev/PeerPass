import 'package:flutter/foundation.dart';

/// A university's grading scale.
///
/// The scale is data, not a hardcoded assumption: a five-point scale and a
/// four-point scale both exist in the pilot's target universities, and the
/// competency threshold is evaluated per scale on the backend. The client
/// carries the scale so it can render a grade, and deliberately carries no
/// threshold logic, because those rules belong to the API.
@immutable
class GradingScale {
  const GradingScale({
    required this.publicId,
    required this.name,
    required this.maxPoints,
  });

  final String publicId;

  /// Human-readable name, for example "4.0 scale" or "5.0 scale".
  final String name;

  /// The highest number of points a grade on this scale can carry.
  final double maxPoints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GradingScale &&
          other.publicId == publicId &&
          other.name == name &&
          other.maxPoints == maxPoints;

  @override
  int get hashCode => Object.hash(publicId, name, maxPoints);

  @override
  String toString() => 'GradingScale($name, max $maxPoints)';
}

/// A single grade achieved on a [GradingScale].
///
/// [isVerified] records that the evidence for the grade was checked. An
/// unverified grade is still displayable, but the backend will not count it
/// toward a tutor competency, so the client needs to distinguish the two when
/// explaining why a tutor is not yet matchable.
@immutable
class Grade {
  const Grade({
    required this.label,
    required this.gradePoints,
    required this.isVerified,
  });

  /// The grade as the university writes it, for example "B+".
  ///
  /// Kept as a string because scales disagree on notation even where the
  /// underlying points agree.
  final String label;

  /// The grade expressed as a number on the owning [GradingScale].
  final double gradePoints;

  final bool isVerified;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Grade &&
          other.label == label &&
          other.gradePoints == gradePoints &&
          other.isVerified == isVerified;

  @override
  int get hashCode => Object.hash(label, gradePoints, isVerified);

  @override
  String toString() => 'Grade($label, $gradePoints, verified: $isVerified)';
}

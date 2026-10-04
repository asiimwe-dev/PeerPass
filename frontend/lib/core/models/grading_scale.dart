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

/// A single grade in a published [GradingScale].
///
/// The backend treats this as a catalogue entry for the institution's official
/// scale, not as a student-specific verification record. A student's verification
/// status belongs to a competency, not to the grade label itself.
@immutable
class Grade {
  const Grade({
    required this.label,
    required this.gradePoints,
    this.maxPoints = 0.0,
  });

  /// The grade as the university writes it, for example "B+".
  ///
  /// Kept as a string because scales disagree on notation even where the
  /// underlying points agree.
  final String label;

  /// The grade expressed as a number on the owning [GradingScale].
  final double gradePoints;

  /// The maximum score on the published scale.
  final double maxPoints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Grade &&
          other.label == label &&
          other.gradePoints == gradePoints &&
          other.maxPoints == maxPoints;

  @override
  int get hashCode => Object.hash(label, gradePoints, maxPoints);

  @override
  String toString() => 'Grade($label, $gradePoints/$maxPoints)';
}

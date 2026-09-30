import 'package:flutter/foundation.dart';

/// A course unit that help requests and tutor competencies are recorded
/// against.
///
/// Naming follows the target universities' own terminology rather than a
/// generic "course", because students search by the unit code their faculty
/// publishes.
@immutable
class CourseUnit {
  const CourseUnit({
    required this.publicId,
    required this.code,
    required this.name,
  });

  final String publicId;

  /// The faculty's unit code, for example "MAT 221".
  final String code;

  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseUnit &&
          other.publicId == publicId &&
          other.code == code &&
          other.name == name;

  @override
  int get hashCode => Object.hash(publicId, code, name);

  @override
  String toString() => 'CourseUnit($code)';
}

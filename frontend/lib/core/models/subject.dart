import 'package:flutter/foundation.dart';

/// A subject or department that tutor competencies are grouped under.
///
/// Distinct from `CourseUnit`: a tutor is competent in a subject across several
/// units, while a help request names one specific unit.
@immutable
class Subject {
  const Subject({required this.publicId, required this.name});

  final String publicId;

  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subject && other.publicId == publicId && other.name == name;

  @override
  int get hashCode => Object.hash(publicId, name);

  @override
  String toString() => 'Subject($name)';
}

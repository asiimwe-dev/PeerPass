import 'package:flutter/foundation.dart';

/// How many live course applications the caller holds, and the cap.
///
/// The number is the server's, not a client constant: the same limit is
/// enforced on submission, and a pilot that raises it should not need a client
/// release before a tutor can apply for another course.
@immutable
class ApplicationLimits {
  const ApplicationLimits({
    required this.activeCount,
    required this.maxActiveCourseUnits,
  });

  /// Reads the wire form.
  ///
  /// Every field is required. A screen that guessed a limit would either hide an
  /// application the tutor is allowed to make or offer one the API will refuse,
  /// and both are worse than reporting a body the client cannot read.
  factory ApplicationLimits.fromJson(Map<String, dynamic> json) {
    final activeCount = json['active_count'];
    final maxActive = json['max_active_course_units'];
    if (activeCount is! int || maxActive is! int) {
      throw const FormatException(
        'application limits were missing a count the screen needs',
      );
    }
    if (activeCount < 0 || maxActive < 1) {
      throw const FormatException('application limits were out of range');
    }
    return ApplicationLimits(
      activeCount: activeCount,
      maxActiveCourseUnits: maxActive,
    );
  }

  /// Pending or verified claims. A rejected claim is not counted.
  final int activeCount;

  /// The configured cap.
  final int maxActiveCourseUnits;

  /// Whether the tutor may not submit another live claim.
  bool get atCap => activeCount >= maxActiveCourseUnits;

  /// How many live applications remain, never below zero.
  int get remainingSlots =>
      (maxActiveCourseUnits - activeCount).clamp(0, maxActiveCourseUnits);
}

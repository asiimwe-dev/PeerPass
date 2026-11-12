import 'package:flutter/foundation.dart';
import 'package:peerpass/core/models/json_decimal.dart';

/// One course's progress towards its own certificate.
///
/// A wire DTO and nothing more. Every threshold question is answered by the API
/// -- [eligible] is its verdict, not a comparison this client makes -- because a
/// client that divided [certifiedMinutes] by [requiredMinutes] itself would hold
/// a second copy of the rule and would go on showing the old one after a pilot
/// lowered it.
///
/// A certificate is earned per course: the hours, sessions, and ratings are the
/// ones recorded against this unit, not a tutor-wide total.
@immutable
class CourseCertificate {
  const CourseCertificate({
    required this.courseUnitId,
    required this.courseUnitCode,
    required this.courseUnitName,
    required this.eligible,
    required this.certifiedMinutes,
    required this.requiredMinutes,
    required this.remainingMinutes,
    required this.completedSessions,
    required this.requiredSessions,
    required this.remainingSessions,
    required this.ratingCount,
    required this.requiredAverageRating,
    required this.minutesMet,
    required this.sessionsMet,
    required this.ratingMet,
    required this.progress,
    this.averageRating,
  });

  /// Reads one course entry.
  ///
  /// Every field is required, including the ones the client could in principle
  /// work out. Defaulting them would mean recomputing the API's arithmetic on a
  /// device, and a body missing them is a contract change rather than a partial
  /// answer -- a [FormatException] the repository turns into a message, which is
  /// what a server fault should look like to a tutor.
  factory CourseCertificate.fromJson(Map<String, dynamic> json) {
    final courseUnitId = json['course_unit_id'];
    final courseUnitCode = json['course_unit_code'];
    final courseUnitName = json['course_unit_name'];
    final eligible = json['eligible'];
    final certifiedMinutes = json['certified_minutes'];
    final requiredMinutes = json['required_minutes'];
    final remainingMinutes = json['remaining_minutes'];
    final completedSessions = json['completed_sessions'];
    final requiredSessions = json['required_sessions'];
    final remainingSessions = json['remaining_sessions'];
    final ratingCount = json['rating_count'];
    final minutesMet = json['minutes_met'];
    final sessionsMet = json['sessions_met'];
    final ratingMet = json['rating_met'];
    final progress = json['progress'];

    if (courseUnitId is! String ||
        courseUnitCode is! String ||
        courseUnitName is! String ||
        eligible is! bool ||
        certifiedMinutes is! num ||
        requiredMinutes is! num ||
        remainingMinutes is! num ||
        completedSessions is! num ||
        requiredSessions is! num ||
        remainingSessions is! num ||
        ratingCount is! num ||
        minutesMet is! bool ||
        sessionsMet is! bool ||
        ratingMet is! bool ||
        progress is! num) {
      throw const FormatException(
        'course certificate was missing a required field',
      );
    }

    return CourseCertificate(
      courseUnitId: courseUnitId,
      courseUnitCode: courseUnitCode,
      courseUnitName: courseUnitName,
      eligible: eligible,
      certifiedMinutes: certifiedMinutes.toInt(),
      requiredMinutes: requiredMinutes.toInt(),
      remainingMinutes: remainingMinutes.toInt(),
      completedSessions: completedSessions.toInt(),
      requiredSessions: requiredSessions.toInt(),
      remainingSessions: remainingSessions.toInt(),
      ratingCount: ratingCount.toInt(),
      averageRating: readDecimal(json['average_rating']),
      requiredAverageRating: readRequiredDecimal(
        json['required_average_rating'],
        'required_average_rating',
      ),
      minutesMet: minutesMet,
      sessionsMet: sessionsMet,
      ratingMet: ratingMet,
      progress: progress.toDouble(),
    );
  }

  /// Public id of the course this certificate is for.
  final String courseUnitId;
  final String courseUnitCode;
  final String courseUnitName;

  /// Whether every requirement has been met for this course.
  final bool eligible;

  /// Minutes taught in this course that counted towards its certificate.
  final int certifiedMinutes;

  /// The configured minutes threshold, as the operator set it.
  final int requiredMinutes;

  /// Minutes still to go in this course. Zero once the minutes condition is met.
  final int remainingMinutes;

  /// Completed sessions in this course.
  final int completedSessions;

  /// The configured session threshold, as the operator set it.
  final int requiredSessions;

  /// Sessions still to go in this course. Zero once the condition is met.
  final int remainingSessions;

  /// How many ratings this course's sessions received.
  final int ratingCount;

  /// The stored mean for this course, or null when it has no ratings.
  final double? averageRating;

  /// The configured minimum mean, as the operator set it.
  final double requiredAverageRating;

  /// Whether the minutes condition is met on its own.
  final bool minutesMet;

  /// Whether the completed-session condition is met on its own.
  final bool sessionsMet;

  /// Whether the rating condition is met on its own.
  final bool ratingMet;

  /// How far along, from 0.0 to 1.0, already clamped by the API.
  final double progress;

  /// The course as a tutor reads it.
  String get courseUnitLabel => '$courseUnitCode · $courseUnitName';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseCertificate &&
          other.courseUnitId == courseUnitId &&
          other.courseUnitCode == courseUnitCode &&
          other.courseUnitName == courseUnitName &&
          other.eligible == eligible &&
          other.certifiedMinutes == certifiedMinutes &&
          other.requiredMinutes == requiredMinutes &&
          other.remainingMinutes == remainingMinutes &&
          other.completedSessions == completedSessions &&
          other.requiredSessions == requiredSessions &&
          other.remainingSessions == remainingSessions &&
          other.ratingCount == ratingCount &&
          other.averageRating == averageRating &&
          other.requiredAverageRating == requiredAverageRating &&
          other.minutesMet == minutesMet &&
          other.sessionsMet == sessionsMet &&
          other.ratingMet == ratingMet &&
          other.progress == progress;

  @override
  int get hashCode => Object.hashAll([
    courseUnitId,
    courseUnitCode,
    courseUnitName,
    eligible,
    certifiedMinutes,
    requiredMinutes,
    remainingMinutes,
    completedSessions,
    requiredSessions,
    remainingSessions,
    ratingCount,
    averageRating,
    requiredAverageRating,
    minutesMet,
    sessionsMet,
    ratingMet,
    progress,
  ]);

  @override
  String toString() =>
      'CourseCertificate($courseUnitCode, '
      '$certifiedMinutes/$requiredMinutes minutes, eligible: $eligible)';
}

/// Every course the signed-in tutor can earn a certificate for.
///
/// The API orders the list earned first, then closest to earned, so [courses]
/// can be rendered as-is and the dashboard can show the first entry without
/// applying an ordering rule of its own.
@immutable
class CertificatePortfolio {
  const CertificatePortfolio({
    required this.hasTutorProfile,
    required this.courses,
  });

  /// Reads the documented response.
  ///
  /// `generated_at` is deliberately not carried. It is the server's clock, and
  /// "as the server saw it" is not what a tutor needs to know; the moment this
  /// screen rendered the numbers is. It stays in the response for whoever needs
  /// it in a log.
  factory CertificatePortfolio.fromJson(Map<String, dynamic> json) {
    final hasTutorProfile = json['has_tutor_profile'];
    final courses = json['courses'];
    if (hasTutorProfile is! bool || courses is! List) {
      throw const FormatException(
        'certificate portfolio was missing a required field',
      );
    }
    return CertificatePortfolio(
      hasTutorProfile: hasTutorProfile,
      courses: [
        for (final course in courses)
          if (course is Map)
            CourseCertificate.fromJson(Map<String, dynamic>.from(course))
          else
            throw const FormatException(
              'a course certificate was not an object',
            ),
      ],
    );
  }

  /// Whether the caller has a tutor profile at all.
  ///
  /// The API's own answer rather than something the client infers from the
  /// caller's roles. A student and a brand-new tutor both have an empty list,
  /// and only one of them is on the path to a certificate.
  final bool hasTutorProfile;

  /// One entry per course, ordered by the server.
  final List<CourseCertificate> courses;

  /// The course the dashboard summarises, or null when there is none.
  CourseCertificate? get leadingCourse =>
      courses.isEmpty ? null : courses.first;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CertificatePortfolio &&
          other.hasTutorProfile == hasTutorProfile &&
          listEquals(other.courses, courses);

  @override
  int get hashCode => Object.hash(hasTutorProfile, Object.hashAll(courses));

  @override
  String toString() =>
      'CertificatePortfolio(${courses.length} courses, '
      'hasTutorProfile: $hasTutorProfile)';
}

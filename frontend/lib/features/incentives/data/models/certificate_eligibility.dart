import 'package:flutter/foundation.dart';
import 'package:peerpass/core/models/json_decimal.dart';

/// The signed-in tutor's standing against the certificate requirements.
///
/// A wire DTO and nothing more. Every threshold question is answered by the API
/// -- [eligible] is its verdict, not a comparison this client makes -- because a
/// client that divided [certifiedMinutes] by [requiredMinutes] itself would hold
/// a second copy of the rule and would go on showing the old one after a pilot
/// lowered it.
///
/// The certificate has three conditions: teaching minutes, completed sessions,
/// and a maintained average rating over enough rated sessions. They travel
/// separately so the screen can say which one is outstanding instead of showing
/// one bar that hides two of them.
@immutable
class CertificateEligibility {
  const CertificateEligibility({
    required this.hasTutorProfile,
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

  /// Reads the wire form.
  ///
  /// Every field is required, including the ones the client could in principle
  /// work out. Defaulting them would mean recomputing the API's arithmetic on a
  /// device, and a body missing them is a contract change rather than a partial
  /// answer -- a [FormatException] the repository turns into a message, which is
  /// what a server fault should look like to a tutor.
  ///
  /// `generated_at` is deliberately not carried. It is the server's clock, and
  /// "as the server saw it" is not what a tutor needs to know; the moment this
  /// screen rendered the numbers is. It stays in the response for whoever needs
  /// it in a log.
  factory CertificateEligibility.fromJson(Map<String, dynamic> json) {
    final hasTutorProfile = json['has_tutor_profile'];
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

    if (hasTutorProfile is! bool ||
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
        'certificate response was missing a required field',
      );
    }

    return CertificateEligibility(
      hasTutorProfile: hasTutorProfile,
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

  /// Whether the caller has a tutor profile at all.
  ///
  /// The API's own answer rather than something the client infers from the
  /// caller's roles. A student and a brand-new tutor both read as zero minutes,
  /// and only one of them is on the path to a certificate; guessing from a role
  /// the client happens to hold would be the client deciding who is a tutor.
  final bool hasTutorProfile;

  /// Whether every requirement has been met. The API's verdict, not this
  /// client's.
  final bool eligible;

  /// Minutes that counted towards a certificate, exactly as stored.
  final int certifiedMinutes;

  /// The configured minutes threshold, as the operator set it.
  final int requiredMinutes;

  /// Minutes still to go. Zero once the minutes condition is met.
  final int remainingMinutes;

  /// Completed sessions the tutor has taught.
  final int completedSessions;

  /// The configured session threshold, as the operator set it.
  final int requiredSessions;

  /// Sessions still to go. Zero once the session condition is met.
  final int remainingSessions;

  /// How many ratings back [averageRating].
  final int ratingCount;

  /// The stored mean, or null when the tutor has no ratings.
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
  ///
  /// The smallest of the three requirement fractions, so it reaches 1.0 only
  /// when all three do.
  final double progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CertificateEligibility &&
          other.hasTutorProfile == hasTutorProfile &&
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
    hasTutorProfile,
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
      'CertificateEligibility($certifiedMinutes/$requiredMinutes minutes, '
      '$completedSessions/$requiredSessions sessions, eligible: $eligible)';
}

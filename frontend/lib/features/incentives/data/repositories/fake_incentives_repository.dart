import 'dart:math' as math;

import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';

/// In-memory stand-in for the incentives endpoints.
///
/// Resolved by widget tests, which have no server to talk to, and seeded rather
/// than computed so a test states the numbers it wants to see on screen. The
/// eligible flag is set from the same three tallies the API would use, rather
/// than being a second field a test has to keep consistent by hand.
///
/// The defaults describe a tutor whose session and rating conditions are already
/// met, so a test that lowers [certifiedMinutes] is testing the minutes gate and
/// nothing else. Pass [completedSessions] or [ratingCount] to make one of the
/// other gates the short one.
class FakeIncentivesRepository implements IncentivesRepository {
  FakeIncentivesRepository({
    this.eligibility,
    this.failure,
    this.hasTutorProfile = true,
    this.certifiedMinutes = 0,
    this.requiredMinutes = 2400,
    this.completedSessions,
    this.requiredSessions = 10,
    this.ratingCount,
    this.averageRating = 4.8,
    this.requiredAverageRating = 4.10,
  });

  /// The answer to return, when the call should succeed.
  final CertificateEligibility? eligibility;

  /// The failure to throw, when the call should fail.
  final Failure? failure;

  /// Whether the fake caller is treated as having a tutor profile.
  final bool hasTutorProfile;

  /// The tally the fake builds its answer from, the way the API would.
  final int certifiedMinutes;

  /// The threshold the fake reports, so a test can state a lowered one.
  final int requiredMinutes;

  /// Completed sessions, or null to meet the configured session threshold.
  final int? completedSessions;

  /// The configured session threshold.
  final int requiredSessions;

  /// Ratings, or null to match the completed-session count.
  final int? ratingCount;

  /// The stored mean, or null for a tutor with no ratings.
  final double? averageRating;

  /// The configured minimum mean.
  final double requiredAverageRating;

  /// How many times [myCertificate] has been called.
  int calls = 0;

  @override
  Future<CertificateEligibility> myCertificate() async {
    calls++;
    final thrown = failure;
    if (thrown != null) throw thrown;
    if (eligibility != null) return eligibility!;

    final sessions = completedSessions ?? requiredSessions;
    final ratings = ratingCount ?? sessions;
    final average = averageRating;

    final minutesMet = certifiedMinutes >= requiredMinutes;
    final sessionsMet = sessions >= requiredSessions;
    final ratingMet =
        ratings >= requiredSessions &&
        average != null &&
        average >= requiredAverageRating;

    return CertificateEligibility(
      hasTutorProfile: hasTutorProfile,
      eligible: minutesMet && sessionsMet && ratingMet,
      certifiedMinutes: certifiedMinutes,
      requiredMinutes: requiredMinutes,
      remainingMinutes: (requiredMinutes - certifiedMinutes).clamp(
        0,
        requiredMinutes,
      ),
      completedSessions: sessions,
      requiredSessions: requiredSessions,
      remainingSessions: (requiredSessions - sessions).clamp(
        0,
        requiredSessions,
      ),
      ratingCount: ratings,
      averageRating: average,
      requiredAverageRating: requiredAverageRating,
      minutesMet: minutesMet,
      sessionsMet: sessionsMet,
      ratingMet: ratingMet,
      // The same limiting-fraction rule the API uses, so the bar a test reads
      // here is drawn from all three conditions rather than from the minutes
      // alone.
      progress: math.min(
        _fraction(certifiedMinutes, requiredMinutes),
        math.min(
          _fraction(sessions, requiredSessions),
          _ratingProgress(ratings, average, requiredSessions),
        ),
      ),
    );
  }

  double _fraction(int value, int required) {
    if (value >= required) return 1;
    return value / required;
  }

  double _ratingProgress(int count, double? average, int requiredCount) {
    if (count < requiredCount) return _fraction(count, requiredCount);
    if (average == null) return 0;
    if (average >= requiredAverageRating) return 1;
    if (average <= 0) return 0;
    return average / requiredAverageRating;
  }
}

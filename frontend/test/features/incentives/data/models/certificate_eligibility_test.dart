import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';

Map<String, dynamic> _body({
  bool hasTutorProfile = true,
  bool eligible = false,
  int certifiedMinutes = 240,
  int requiredMinutes = 2400,
  int? remainingMinutes,
  int completedSessions = 0,
  int requiredSessions = 10,
  int? remainingSessions,
  int ratingCount = 0,
  String? averageRating,
  String requiredAverageRating = '4.10',
  bool minutesMet = false,
  bool sessionsMet = false,
  bool ratingMet = false,
  double? progress,
  Object? progressOverride,
}) {
  return {
    'has_tutor_profile': hasTutorProfile,
    'eligible': eligible,
    'certified_minutes': certifiedMinutes,
    'required_minutes': requiredMinutes,
    'remaining_minutes': remainingMinutes ?? requiredMinutes - certifiedMinutes,
    'completed_sessions': completedSessions,
    'required_sessions': requiredSessions,
    'remaining_sessions':
        remainingSessions ?? requiredSessions - completedSessions,
    'rating_count': ratingCount,
    'average_rating': averageRating,
    'required_average_rating': requiredAverageRating,
    'minutes_met': minutesMet,
    'sessions_met': sessionsMet,
    'rating_met': ratingMet,
    'progress':
        progressOverride ?? progress ?? certifiedMinutes / requiredMinutes,
    'generated_at': '2026-03-04T11:00:00Z',
  };
}

void main() {
  group('fromJson', () {
    test('reads every field the screen renders', () {
      final eligibility = CertificateEligibility.fromJson(
        _body(
          certifiedMinutes: 2399,
          remainingMinutes: 1,
          completedSessions: 4,
          ratingCount: 7,
          averageRating: '4.75',
          progress: 0.4,
        ),
      );

      expect(eligibility.hasTutorProfile, isTrue);
      expect(eligibility.eligible, isFalse);
      expect(eligibility.certifiedMinutes, 2399);
      expect(eligibility.requiredMinutes, 2400);
      expect(eligibility.remainingMinutes, 1);
      expect(eligibility.completedSessions, 4);
      expect(eligibility.requiredSessions, 10);
      expect(eligibility.remainingSessions, 6);
      expect(eligibility.ratingCount, 7);
      expect(eligibility.averageRating, 4.75);
      expect(eligibility.requiredAverageRating, 4.10);
      expect(eligibility.minutesMet, isFalse);
      expect(eligibility.sessionsMet, isFalse);
      expect(eligibility.ratingMet, isFalse);
      expect(eligibility.progress, 0.4);
    });

    test('reads the average rating from the decimal string the API sends', () {
      // `MeanRating` is a `Decimal` and Pydantic serialises it as a JSON
      // string, so the client must not assume a JSON number arrives.
      final eligibility = CertificateEligibility.fromJson(
        _body(averageRating: '4.10', requiredAverageRating: '4.50'),
      );

      expect(eligibility.averageRating, 4.10);
      expect(eligibility.requiredAverageRating, 4.50);
    });

    test('reads the threshold the operator configured, not a shipped one', () {
      // A pilot that lowers the bar to 600 must not need a client change, so the
      // number is read rather than assumed. This is the client-side half of the
      // same promise the backend test makes about Settings.
      final eligibility = CertificateEligibility.fromJson(
        _body(certifiedMinutes: 600, requiredMinutes: 600, remainingMinutes: 0),
      );

      expect(eligibility.requiredMinutes, 600);
      expect(eligibility.eligible, isFalse);
      expect(eligibility.remainingMinutes, 0);
    });

    test('keeps the API verdict rather than recomputing it', () {
      // An eligible answer with minutes one short of the threshold is what a
      // server that rounds, or counts a partial session, would send. The client
      // shows what it was told; it does not second-guess it.
      final eligibility = CertificateEligibility.fromJson(
        _body(eligible: true, certifiedMinutes: 2399, remainingMinutes: 1),
      );

      expect(eligibility.eligible, isTrue);
    });

    test('reads a caller with no tutor profile as zero, not as an error', () {
      final eligibility = CertificateEligibility.fromJson(
        _body(hasTutorProfile: false, certifiedMinutes: 0, remainingMinutes: 0),
      );

      expect(eligibility.hasTutorProfile, isFalse);
      expect(eligibility.certifiedMinutes, 0);
      expect(eligibility.eligible, isFalse);
    });

    for (final field in [
      'has_tutor_profile',
      'eligible',
      'certified_minutes',
      'required_minutes',
      'remaining_minutes',
      'completed_sessions',
      'required_sessions',
      'remaining_sessions',
      'rating_count',
      'required_average_rating',
      'minutes_met',
      'sessions_met',
      'rating_met',
      'progress',
    ]) {
      test('throws when $field is absent, rather than inventing it', () {
        final body = _body()..remove(field);

        expect(
          () => CertificateEligibility.fromJson(body),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('throws when progress is a string rather than a number', () {
      expect(
        () => CertificateEligibility.fromJson(_body(progressOverride: 'half')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('equality', () {
    test('is by value, so a rebuilt answer does not look new', () {
      expect(
        CertificateEligibility.fromJson(_body()),
        CertificateEligibility.fromJson(_body()),
      );
    });

    test('separates answers that differ', () {
      expect(
        CertificateEligibility.fromJson(_body(certifiedMinutes: 10)),
        isNot(CertificateEligibility.fromJson(_body(certifiedMinutes: 11))),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';

Map<String, dynamic> _body({
  bool hasTutorProfile = true,
  bool eligible = false,
  int certifiedMinutes = 240,
  int requiredMinutes = 2400,
  int? remainingMinutes,
  double? progress,
  Object? progressOverride,
}) {
  return {
    'has_tutor_profile': hasTutorProfile,
    'eligible': eligible,
    'certified_minutes': certifiedMinutes,
    'required_minutes': requiredMinutes,
    'remaining_minutes': remainingMinutes ?? requiredMinutes - certifiedMinutes,
    'progress': progressOverride ?? progress ?? certifiedMinutes / requiredMinutes,
    'generated_at': '2026-03-04T11:00:00Z',
  };
}

void main() {
  group('fromJson', () {
    test('reads every field the screen renders', () {
      final eligibility = CertificateEligibility.fromJson(
        _body(certifiedMinutes: 2399, remainingMinutes: 1, progress: 2399 / 2400),
      );

      expect(eligibility.hasTutorProfile, isTrue);
      expect(eligibility.eligible, isFalse);
      expect(eligibility.certifiedMinutes, 2399);
      expect(eligibility.requiredMinutes, 2400);
      expect(eligibility.remainingMinutes, 1);
      expect(eligibility.progress, closeTo(0.99958, 0.00001));
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

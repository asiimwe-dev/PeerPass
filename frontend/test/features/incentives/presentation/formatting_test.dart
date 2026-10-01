import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/presentation/formatting.dart';

CertificateEligibility _eligibility({
  bool eligible = false,
  int certifiedMinutes = 0,
  int requiredMinutes = 2400,
  int? remainingMinutes,
  double progress = 0,
}) {
  return CertificateEligibility(
    hasTutorProfile: true,
    eligible: eligible,
    certifiedMinutes: certifiedMinutes,
    requiredMinutes: requiredMinutes,
    remainingMinutes:
        remainingMinutes ?? (requiredMinutes - certifiedMinutes).clamp(0, 1 << 30),
    progress: progress,
  );
}

void main() {
  group('hoursAndMinutes', () {
    test('drops the minutes when they land on the hour', () {
      expect(hoursAndMinutes(0), '0h');
      expect(hoursAndMinutes(120), '2h');
      expect(hoursAndMinutes(2400), '40h');
    });

    test('keeps the minutes when they do not', () {
      expect(hoursAndMinutes(90), '1h 30m');
      expect(hoursAndMinutes(61), '1h 1m');
    });

    test('does not round a shortfall up to the hour it is short of', () {
      // The whole reason this screen exists. Rounding here would print "40h of 40h"
      // for a tutor one minute short of a certificate.
      expect(hoursAndMinutes(2399), '39h 59m');
    });
  });

  group('certificateProgressLabel', () {
    test('counts the hours banked against the hours required', () {
      expect(
        certificateProgressLabel(
          _eligibility(certifiedMinutes: 600),
        ),
        '10h of 40h',
      );
    });

    test('says earned and nothing else once the API says so', () {
      expect(
        certificateProgressLabel(
          _eligibility(
            eligible: true,
            certifiedMinutes: 2400,
            remainingMinutes: 0,
          ),
        ),
        'Certificate earned',
      );
    });
  });

  group('remainingLabel', () {
    test('is nothing once earned, so no count can contradict the verdict', () {
      expect(
        remainingLabel(
          _eligibility(
            eligible: true,
            certifiedMinutes: 3000,
            remainingMinutes: 0,
          ),
        ),
        isNull,
      );
    });

    test('reads in hours when the shortfall is more than an hour', () {
      expect(
        remainingLabel(_eligibility(certifiedMinutes: 1800)),
        '10h to go',
      );
    });

    test('reads in minutes when the shortfall is under an hour', () {
      expect(remainingLabel(_eligibility(remainingMinutes: 30)), '30 minutes to go');
      expect(remainingLabel(_eligibility(remainingMinutes: 1)), '1 minute to go');
    });
  });

  group('progressValue', () {
    test('passes a value inside the scale through', () {
      expect(progressValue(_eligibility(progress: 0.5)), 0.5);
    });

    test('clamps a value outside it rather than letting the bar throw', () {
      expect(progressValue(_eligibility(progress: 1.4)), 1.0);
      expect(progressValue(_eligibility(progress: -0.2)), 0.0);
      expect(progressValue(_eligibility(progress: double.nan)), 0.0);
    });
  });
}

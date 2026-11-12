import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/incentives/data/models/certificate_portfolio.dart';
import 'package:peerpass/features/incentives/presentation/formatting.dart';

CourseCertificate _course({
  bool eligible = false,
  int certifiedMinutes = 0,
  int requiredMinutes = 2400,
  int? remainingMinutes,
  int completedSessions = 10,
  int requiredSessions = 10,
  int? remainingSessions,
  int ratingCount = 10,
  double? averageRating = 4.8,
  double requiredAverageRating = 4.10,
  bool? minutesMet,
  bool? sessionsMet,
  bool? ratingMet,
  double progress = 0,
}) {
  return CourseCertificate(
    courseUnitId: 'unit-1',
    courseUnitCode: 'BIT 221',
    courseUnitName: 'Operating Systems',
    eligible: eligible,
    certifiedMinutes: certifiedMinutes,
    requiredMinutes: requiredMinutes,
    remainingMinutes:
        remainingMinutes ??
        (requiredMinutes - certifiedMinutes).clamp(0, 1 << 30),
    completedSessions: completedSessions,
    requiredSessions: requiredSessions,
    remainingSessions:
        remainingSessions ??
        (requiredSessions - completedSessions).clamp(0, 1 << 30),
    ratingCount: ratingCount,
    averageRating: averageRating,
    requiredAverageRating: requiredAverageRating,
    minutesMet: minutesMet ?? certifiedMinutes >= requiredMinutes,
    sessionsMet: sessionsMet ?? completedSessions >= requiredSessions,
    ratingMet:
        ratingMet ??
        (ratingCount >= requiredSessions &&
            averageRating != null &&
            averageRating >= requiredAverageRating),
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
        certificateProgressLabel(_course(certifiedMinutes: 600)),
        '10h of 40h',
      );
    });

    test('says earned and nothing else once the API says so', () {
      expect(
        certificateProgressLabel(
          _course(eligible: true, certifiedMinutes: 2400, remainingMinutes: 0),
        ),
        'Certificate earned',
      );
    });

    test('names the sessions once the hours are already banked', () {
      // The bar is the limiting fraction. Continuing to describe the hours here
      // would put "135h 52m of 40h" over a half-full bar.
      expect(
        certificateProgressLabel(
          _course(
            certifiedMinutes: 8152,
            completedSessions: 4,
            remainingSessions: 6,
          ),
        ),
        '4 of 10 sessions',
      );
    });

    test('names the ratings while the count is still short', () {
      expect(
        certificateProgressLabel(
          _course(certifiedMinutes: 2400, ratingCount: 8),
        ),
        '8 of 10 ratings',
      );
    });

    test('names the average when only the average is short', () {
      expect(
        certificateProgressLabel(
          _course(certifiedMinutes: 2400, averageRating: 3.5),
        ),
        'Average 3.50 of 4.10',
      );
    });
  });

  group('remainingLabel', () {
    test('is nothing once earned, so no count can contradict the verdict', () {
      expect(
        remainingLabel(
          _course(eligible: true, certifiedMinutes: 3000, remainingMinutes: 0),
        ),
        isNull,
      );
    });

    test('reads in hours when the shortfall is more than an hour', () {
      expect(remainingLabel(_course(certifiedMinutes: 1800)), '10h to go');
    });

    test('reads in minutes when the shortfall is under an hour', () {
      expect(remainingLabel(_course(remainingMinutes: 30)), '30 minutes to go');
      expect(remainingLabel(_course(remainingMinutes: 1)), '1 minute to go');
    });

    test('counts sessions once the hours are in', () {
      expect(
        remainingLabel(
          _course(
            certifiedMinutes: 2400,
            completedSessions: 4,
            remainingSessions: 6,
          ),
        ),
        '6 more sessions to go',
      );
    });

    test('counts the ratings still needed', () {
      expect(
        remainingLabel(_course(certifiedMinutes: 2400, ratingCount: 8)),
        '2 more ratings needed',
      );
    });

    test('names the average when the rating count is already there', () {
      expect(
        remainingLabel(_course(certifiedMinutes: 2400, averageRating: 3.5)),
        'Average needs to reach 4.10',
      );
    });
  });

  group('certificateRequirements', () {
    test('lists all three conditions with the API verdict for each', () {
      final requirements = certificateRequirements(
        _course(
          certifiedMinutes: 2400,
          completedSessions: 4,
          remainingSessions: 6,
          ratingCount: 8,
          averageRating: 4.75,
        ),
      );

      expect(requirements, hasLength(3));
      expect(requirements[0].label, 'Teaching hours');
      expect(requirements[0].value, '40h banked · 40h needed');
      expect(requirements[0].met, isTrue);
      expect(requirements[1].label, 'Sessions completed');
      expect(requirements[1].value, '4 of 10');
      expect(requirements[1].met, isFalse);
      expect(requirements[2].label, 'Average rating');
      expect(requirements[2].value, '4.75 from 8 of 10 ratings');
      expect(requirements[2].met, isFalse);
    });

    test('says "no ratings yet" rather than showing a made-up mean', () {
      final requirements = certificateRequirements(
        _course(certifiedMinutes: 2400, ratingCount: 0, averageRating: null),
      );

      expect(requirements[2].value, 'No ratings yet — needs 4.10');
      expect(requirements[2].met, isFalse);
    });

    test('reads the maintained average once the count is met', () {
      expect(
        certificateRequirements(_course(certifiedMinutes: 2400))[2].value,
        '4.80 over 10 ratings',
      );
      expect(
        certificateRequirements(
          _course(certifiedMinutes: 2400, averageRating: 3.5),
        )[2].value,
        '3.50 — needs 4.10',
      );
    });
  });

  group('progressValue', () {
    test('passes a value inside the scale through', () {
      expect(progressValue(_course(progress: 0.5)), 0.5);
    });

    test('clamps a value outside it rather than letting the bar throw', () {
      expect(progressValue(_course(progress: 1.4)), 1.0);
      expect(progressValue(_course(progress: -0.2)), 0.0);
      expect(progressValue(_course(progress: double.nan)), 0.0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/incentives/data/models/certificate_portfolio.dart';

Map<String, dynamic> _course({
  String courseUnitId = 'unit-1',
  String courseUnitCode = 'BIT 221',
  String courseUnitName = 'Operating Systems',
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
    'course_unit_id': courseUnitId,
    'course_unit_code': courseUnitCode,
    'course_unit_name': courseUnitName,
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
  };
}

Map<String, dynamic> _body({
  bool hasTutorProfile = true,
  List<Map<String, dynamic>>? courses,
  String generatedAt = '2026-03-04T11:00:00Z',
}) {
  return {
    'has_tutor_profile': hasTutorProfile,
    'courses': courses ?? [_course()],
    'generated_at': generatedAt,
  };
}

void main() {
  group('reading a course certificate', () {
    test('reads every field the screen renders', () {
      final course = CourseCertificate.fromJson(
        _course(
          certifiedMinutes: 2399,
          remainingMinutes: 1,
          completedSessions: 4,
          ratingCount: 7,
          averageRating: '4.75',
          progress: 0.4,
        ),
      );

      expect(course.courseUnitId, 'unit-1');
      expect(course.courseUnitCode, 'BIT 221');
      expect(course.courseUnitName, 'Operating Systems');
      expect(course.eligible, isFalse);
      expect(course.certifiedMinutes, 2399);
      expect(course.requiredMinutes, 2400);
      expect(course.remainingMinutes, 1);
      expect(course.completedSessions, 4);
      expect(course.requiredSessions, 10);
      expect(course.remainingSessions, 6);
      expect(course.ratingCount, 7);
      expect(course.averageRating, 4.75);
      expect(course.requiredAverageRating, 4.10);
      expect(course.minutesMet, isFalse);
      expect(course.sessionsMet, isFalse);
      expect(course.ratingMet, isFalse);
      expect(course.progress, 0.4);
    });

    test('reads the average rating from the decimal string the API sends', () {
      // `MeanRating` is a `Decimal` and Pydantic serialises it as a JSON
      // string, so the client must not assume a JSON number arrives.
      final course = CourseCertificate.fromJson(
        _course(averageRating: '4.10', requiredAverageRating: '4.50'),
      );

      expect(course.averageRating, 4.10);
      expect(course.requiredAverageRating, 4.50);
    });

    test('reads the threshold the operator configured, not a shipped one', () {
      // A pilot that lowers the bar to 600 must not need a client change, so the
      // number is read rather than assumed. This is the client-side half of the
      // same promise the backend test makes about Settings.
      final course = CourseCertificate.fromJson(
        _course(
          certifiedMinutes: 600,
          requiredMinutes: 600,
          remainingMinutes: 0,
        ),
      );

      expect(course.requiredMinutes, 600);
      expect(course.eligible, isFalse);
      expect(course.remainingMinutes, 0);
    });

    test('keeps the API verdict rather than recomputing it', () {
      // An eligible answer with minutes one short of the threshold is what a
      // server that rounds, or counts a partial session, would send. The client
      // shows what it was told; it does not second-guess it.
      final course = CourseCertificate.fromJson(
        _course(eligible: true, certifiedMinutes: 2399, remainingMinutes: 1),
      );

      expect(course.eligible, isTrue);
    });

    test('reads a course with no ratings as null, not as zero', () {
      final course = CourseCertificate.fromJson(_course());

      expect(course.averageRating, isNull);
      expect(course.ratingMet, isFalse);
    });

    test('presents the course as a tutor reads it', () {
      expect(
        CourseCertificate.fromJson(_course()).courseUnitLabel,
        'BIT 221 · Operating Systems',
      );
    });

    for (final field in [
      'course_unit_id',
      'course_unit_code',
      'course_unit_name',
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
        final body = _course()..remove(field);

        expect(
          () => CourseCertificate.fromJson(body),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('throws when progress is a string rather than a number', () {
      expect(
        () => CourseCertificate.fromJson(_course(progressOverride: 'half')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('reading a certificate portfolio', () {
    test('reads every course in the order the API sent them', () {
      final portfolio = CertificatePortfolio.fromJson(
        _body(
          courses: [
            _course(eligible: true, progress: 1),
            _course(courseUnitCode: 'BIT 223', progress: 0.4),
            _course(courseUnitCode: 'BIT 225', progress: 0.1),
          ],
        ),
      );

      expect(portfolio.hasTutorProfile, isTrue);
      expect(portfolio.courses.map((course) => course.courseUnitCode), [
        'BIT 221',
        'BIT 223',
        'BIT 225',
      ]);
      // The order is the server's, so the card that shows one course shows the
      // first entry unchanged.
      expect(portfolio.leadingCourse?.courseUnitCode, 'BIT 221');
    });

    test('a caller with no tutor profile is a real answer, not an error', () {
      final portfolio = CertificatePortfolio.fromJson(
        _body(hasTutorProfile: false, courses: []),
      );

      expect(portfolio.hasTutorProfile, isFalse);
      expect(portfolio.courses, isEmpty);
      expect(portfolio.leadingCourse, isNull);
    });

    test('a tutor with no verified course has a profile and no courses', () {
      final portfolio = CertificatePortfolio.fromJson(_body(courses: []));

      expect(portfolio.hasTutorProfile, isTrue);
      expect(portfolio.courses, isEmpty);
      expect(portfolio.leadingCourse, isNull);
    });

    test('throws when the profile flag is missing', () {
      final body = _body()..remove('has_tutor_profile');

      expect(
        () => CertificatePortfolio.fromJson(body),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when courses is not a list', () {
      final body = _body()..['courses'] = 'BIT 221';

      expect(
        () => CertificatePortfolio.fromJson(body),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when an entry is not an object', () {
      final body = _body(courses: [])..['courses'] = ['BIT 221'];

      expect(
        () => CertificatePortfolio.fromJson(body),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('equality', () {
    test('is by value, so a rebuilt answer does not look new', () {
      expect(
        CertificatePortfolio.fromJson(_body()),
        CertificatePortfolio.fromJson(_body()),
      );
    });

    test('separates portfolios whose courses differ', () {
      expect(
        CertificatePortfolio.fromJson(
          _body(courses: [_course(certifiedMinutes: 10)]),
        ),
        isNot(
          CertificatePortfolio.fromJson(
            _body(courses: [_course(certifiedMinutes: 11)]),
          ),
        ),
      );
    });

    test('separates portfolios that differ in course order', () {
      expect(
        CertificatePortfolio.fromJson(
          _body(
            courses: [
              _course(courseUnitCode: 'A'),
              _course(courseUnitCode: 'B'),
            ],
          ),
        ),
        isNot(
          CertificatePortfolio.fromJson(
            _body(
              courses: [
                _course(courseUnitCode: 'B'),
                _course(courseUnitCode: 'A'),
              ],
            ),
          ),
        ),
      );
    });
  });
}

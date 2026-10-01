import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';

Map<String, dynamic> _tutor({String id = 'tutor-1', String? rating = '4.10'}) {
  return {
    'user_id': id,
    'full_name': 'Grace Okello',
    'standing': 'verified',
    'average_rating': ?rating,
    'completed_sessions': 12,
  };
}

Map<String, dynamic> _candidate({
  String id = 'tutor-1',
  Object? gradePoints = '82.50',
  Object? score = 0.93,
  Object? meets = true,
}) {
  return {
    'tutor': _tutor(id: id),
    'course_unit_id': 'unit-1',
    'competency_grade_points': ?gradePoints,
    'meets_threshold': ?meets,
    'score': ?score,
  };
}

Map<String, dynamic> _response({
  Object? candidates = const <Object>[],
  Object? exclusions = const <Object>[],
  Object? widened,
  Object? none,
  Object? requestId,
}) {
  return {
    'course_unit_id': 'unit-1',
    'generated_at': '2026-03-04T09:12:00Z',
    'candidates': ?candidates,
    'exclusions': ?exclusions,
    'widened': ?widened,
    'no_eligible_tutors': ?none,
    'request_id': ?requestId,
  };
}

void main() {
  group('the response the unit-only route returns', () {
    test('is read whole, and a widened search is not read as an exact one', () {
      final result = MatchResult.fromJson(
        _response(
          candidates: [_candidate()],
          exclusions: [
            {'tutor_id': 'tutor-2', 'reason': 'below_threshold'},
          ],
          widened: true,
        ),
      );

      expect(result.courseUnitId, 'unit-1');
      expect(result.widened, isTrue);
      expect(result.candidates.single.tutor.fullName, 'Grace Okello');
      expect(
        result.exclusions.single.reason,
        MatchExclusionReason.belowThreshold,
      );
      expect(result.generatedAt, DateTime.utc(2026, 3, 4, 9, 12));
      // The unit-only query has no help request behind it, so the response's null
      // must not become a string the client could later try to follow.
      expect(result.requestId, isNull);
    });

    test(
      'a null request id stays null rather than becoming an empty string',
      () {
        expect(MatchResult.fromJson(_response()).requestId, isNull);
        expect(
          MatchResult.fromJson(_response(requestId: '')).requestId,
          isNull,
        );
        expect(
          MatchResult.fromJson(_response(requestId: 'request-1')).requestId,
          'request-1',
        );
      },
    );
  });

  group('nobody being eligible is a result, not an absence', () {
    test('is read from the flag the API sends for it', () {
      final result = MatchResult.fromJson(_response(none: true, widened: true));

      expect(result.noEligibleTutors, isTrue);
      expect(result.widened, isTrue);
      expect(result.candidates, isEmpty);
    });

    test('is not inferred from an empty candidate list', () {
      // A response with neither the flag nor candidates is not a claim that
      // nobody is eligible; it is a response that says nothing about it. Defaulting
      // the flag to true here would let a truncated response produce an empty
      // state telling a student there are no tutors.
      expect(MatchResult.fromJson(_response()).noEligibleTutors, isFalse);
      expect(
        MatchResult.fromJson(_response(candidates: [])).noEligibleTutors,
        isFalse,
      );
    });
  });

  group('a candidate', () {
    test('reads grade points as the decimal string the wire carries', () {
      // "82.50" not 82.5: a JSON number here would come back as a double that
      // cannot represent every numeric(6,2) value, and the value is only ever
      // displayed. Reading the string is what keeps 82.5 showing as 82.5.
      final candidate = MatchCandidate.fromJson(_candidate());

      expect(candidate.competencyGradePoints, 82.5);
      expect(candidate.gradeLabel, 'Grade points 82.5');
    });

    test('says so when the API sent no grade points', () {
      // Null is a real value: the engine proposes tutors it thinks are eligible,
      // and a response that leaves the grade off is not one to refuse.
      final candidate = MatchCandidate.fromJson(_candidate(gradePoints: null));

      expect(candidate.competencyGradePoints, isNull);
      expect(candidate.gradeLabel, 'Grade not on record');
    });

    test('is refused when it has no tutor or no score', () {
      // A candidate with no score has nothing to rank, and one with no tutor has
      // no name to show. Either would render as a blank card.
      expect(
        () => MatchCandidate.fromJson(const {
          'course_unit_id': 'unit-1',
          'score': 0.9,
        }),
        throwsFormatException,
      );
      expect(
        () => MatchCandidate.fromJson({
          'course_unit_id': 'unit-1',
          'tutor': _tutor(),
        }),
        throwsFormatException,
      );
    });

    test('reads a numeric score as a double', () {
      // `score` is a real JSON number, unlike the Decimal fields, so it must not
      // be read as a string.
      final candidate = MatchCandidate.fromJson(_candidate(score: 1));

      expect(candidate.score, 1.0);
    });

    test(
      'a missing meets_threshold does not assert the tutor failed the bar',
      () {
        // The default is the reading that does not make a claim the server did not:
        // the engine proposed this tutor, so treat it as eligible rather than
        // recording it as having failed a competency gate.
        expect(
          MatchCandidate.fromJson(_candidate(meets: null)).meetsThreshold,
          isTrue,
        );
      },
    );
  });

  group('an exclusion', () {
    test('parses a code this build knows', () {
      final exclusion = MatchExclusion.fromJson(const {
        'tutor_id': 'tutor-2',
        'reason': 'unverified',
      });

      expect(exclusion.reason, MatchExclusionReason.unverified);
      expect(exclusion.explanation, isNotEmpty);
    });

    test('a code from a newer server is kept, and reported as unknown', () {
      // Dropping it would make a tutor who was considered disappear without
      // trace, which is the one thing the exclusion list exists to prevent.
      final exclusion = MatchExclusion.fromJson(const {
        'tutor_id': 'tutor-2',
        'reason': 'under_academic_standing',
      });

      expect(exclusion.reason, isNull);
      expect(exclusion.reasonWire, 'under_academic_standing');
      expect(exclusion.explanation, contains('could not say'));
    });

    test('is refused without a tutor or a reason', () {
      expect(
        () => MatchExclusion.fromJson(const {'reason': 'suspended'}),
        throwsFormatException,
      );
      expect(
        () => MatchExclusion.fromJson(const {
          'tutor_id': 'tutor-2',
          'reason': '',
        }),
        throwsFormatException,
      );
    });
  });

  test('a response with no unit or no time is refused', () {
    // Without the unit a screen could not say which course it is looking at, and
    // without the time it could not say when the answer was true. Neither has a
    // neutral reading, so neither is defaulted.
    expect(
      () =>
          MatchResult.fromJson(const {'generated_at': '2026-03-04T09:12:00Z'}),
      throwsFormatException,
    );
    expect(
      () => MatchResult.fromJson(const {'course_unit_id': 'unit-1'}),
      throwsFormatException,
    );
  });

  test('a malformed timestamp is refused rather than read as the epoch', () {
    expect(
      () => MatchResult.fromJson(const {
        'course_unit_id': 'unit-1',
        'generated_at': 'not a date',
      }),
      throwsFormatException,
    );
  });

  test('absent lists read as empty', () {
    final result = MatchResult.fromJson(const {
      'course_unit_id': 'unit-1',
      'generated_at': '2026-03-04T09:12:00Z',
    });

    expect(result.candidates, isEmpty);
    expect(result.exclusions, isEmpty);
    expect(result.excludedCount, 0);
  });
}

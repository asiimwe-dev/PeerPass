import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';
import 'package:peerpass/features/matching/data/repositories/matching_repository.dart';

/// In-memory stand-in for the matching endpoints.
///
/// What widget tests resolve, because a widget test has no server to talk to. It
/// implements the repository's shape rather than the datasource's, because that
/// is the seam a test cares about: overriding the repository is the only
/// composition the app supports.
///
/// A fake and not a stub in the two places a stub would hide a bug. It records
/// what it was asked, so a test can prove the screen sent the unit it was given
/// and the widening flag the student chose. And its default answer is "nobody is
/// eligible for this unit" -- the honest response -- rather than an empty
/// response that reads as success with nothing in it.
class FakeMatchingRepository implements MatchingRepository {
  FakeMatchingRepository({
    List<CourseUnit> courseUnits = const [],
    this.onSuggestions,
    this.defaultResult,
  }) : _courseUnits = List<CourseUnit>.of(courseUnits);

  final List<CourseUnit> _courseUnits;

  /// The answer every query gets when [onSuggestions] does not script one.
  final MatchResult? defaultResult;

  /// Answers each call from the arguments it was given.
  ///
  /// The seam for a test that needs the answer to depend on the query -- a
  /// widened search, a unit with nobody eligible -- because the same screen has
  /// to render both and a repository that returned one fixed body could only
  /// prove half of it.
  final MatchResult Function({
    required String courseUnitId,
    required bool widenToSubject,
  })?
  onSuggestions;

  /// Every `(courseUnitId, widenToSubject)` pair asked for, in order.
  final List<({String courseUnitId, bool widenToSubject})> queries = [];

  /// The course units the picker offers.
  List<CourseUnit> get catalogue => List<CourseUnit>.unmodifiable(_courseUnits);

  @override
  Future<List<CourseUnit>> courseUnits({String? universityId}) async =>
      List<CourseUnit>.unmodifiable(_courseUnits);

  @override
  Future<MatchResult> suggestions({
    required String courseUnitId,
    bool widenToSubject = false,
    int? limit,
  }) async {
    queries.add((courseUnitId: courseUnitId, widenToSubject: widenToSubject));

    final scripted = onSuggestions?.call(
      courseUnitId: courseUnitId,
      widenToSubject: widenToSubject,
    );
    if (scripted != null) return scripted;

    return defaultResult ??
        MatchResult(
          courseUnitId: courseUnitId,
          widened: false,
          candidates: const [],
          exclusions: const [],
          noEligibleTutors: true,
          generatedAt: DateTime.utc(2026, 3, 4, 9, 12),
        );
  }
}

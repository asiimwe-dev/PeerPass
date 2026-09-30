import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';

/// The matching contract the screens depend on.
///
/// Every method throws a [Failure], never a transport exception and never a
/// `FormatException`. Translating `DioException`, problem documents, and
/// unparseable bodies into [Failure] happens in the implementation, so a screen
/// renders a message and never has to know whether the API answered with a socket
/// error, a 422, or a body that was not the shape it documents.
///
/// Narrow on purpose. Help requests are not here: creating one, listing them, and
/// opening one have no screen in this release, and a contract with methods
/// nothing calls is a description of an intention rather than of the client.
abstract interface class MatchingRepository {
  /// The course units this student may pick, for their own university.
  ///
  /// Reference data, read to fill the picker. The API answers a university it does
  /// not have with an empty list rather than a 404, which is what lets a picker
  /// filtered on a stale value show nothing instead of failing.
  Future<List<CourseUnit>> courseUnits({String? universityId});

  /// Who may take this course unit, in the API's ranking.
  ///
  /// [widenToSubject] is the one search behaviour a client may request and it is
  /// opt-in, because widening by default would return tutors who cannot help with
  /// the course the student asked about. When it is asked for and the exact unit
  /// has nobody, the answer says so in [MatchResult.widened] rather than
  /// returning a wider list as though it were the answer to this question.
  ///
  /// "Nobody at all" is a [MatchResult] with
  /// [MatchResult.noEligibleTutors] set, not a failure. A student whose unit has
  /// no eligible tutor has been told something true and actionable, and
  /// rendering that as an error would be a lie about the platform.
  Future<MatchResult> suggestions({
    required String courseUnitId,
    bool widenToSubject = false,
    int? limit,
  });
}

/// The matching contract, as a live instance.
///
/// Declared in the contract file rather than beside the matching screens, for
/// the same reason `sessionsRepositoryProvider` is: this is the handle by which
/// another feature would reach this feature, and a provider living in
/// `presentation/` could not be imported without dragging the screens along.
///
/// Throwing rather than defaulting keeps a missing override loud. A silent fake
/// default would let a build ship with a picker that finds no tutors and a
/// results screen that says nobody is eligible -- two very different claims from
/// one missing line in the composition root.
final matchingRepositoryProvider = Provider<MatchingRepository>(
  (ref) => throw UnimplementedError(
    'matchingRepositoryProvider must be overridden in ProviderScope.',
  ),
);

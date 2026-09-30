import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/features/tutors/data/models/tutor_detail.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';

/// The tutor-discovery contract the screens depend on.
///
/// Every method throws a [Failure], never a transport exception and never a
/// `FormatException`. Translating `DioException`, problem documents, and
/// unparseable bodies into [Failure] happens in the implementation, so a screen
/// renders a message and never has to know whether the API answered with a
/// socket error, a 422, or a body that was not the shape it documents.
abstract interface class TutorsRepository {
  /// The tutors to browse, most endorsed first, at the caller's own university.
  ///
  /// An empty list is a normal answer and not a failure: a university with no
  /// eligible tutor yet, and a filter on a unit the API no longer has, both come
  /// back as `[]`. The screen's empty state is what says which of the two it is.
  ///
  /// A caller with no university gets a `ValidationFailure` naming
  /// `university_id`, because the rail is defined as their own university's
  /// tutors and there is nothing sensible to fall back to.
  Future<List<TutorRailEntry>> topTutors({String? courseUnitId});

  /// One tutor's public profile, by public id.
  ///
  /// A `NotFoundFailure` for a user who is not a tutor and for one who does not
  /// exist. The API answers both the same way on purpose, and the client does
  /// not distinguish them either.
  Future<TutorDetail> tutor(String userId);

  /// The course units endorsements are recorded against.
  ///
  /// Here to give an endorsed unit id a name on the detail screen. Not a
  /// matching input: which units a tutor is eligible for is the API's answer,
  /// and nothing here derives it.
  Future<List<CourseUnit>> courseUnits({String? universityId});
}

/// The tutor-discovery contract, as a live instance.
///
/// Declared in the contract file rather than beside the tutors screens, for the
/// same reason `sessionsRepositoryProvider` is: this is the handle by which
/// other features reach this feature, and a provider living in `presentation/`
/// could not be imported by a sibling feature without also importing its
/// screens.
///
/// Throwing rather than defaulting keeps a missing override loud. A silent fake
/// default would let a build ship with an empty rail that looks like a
/// university with no tutors in it, and it is the failure this provider exists
/// to make visible: the composition root in `main.dart` is what has to name the
/// real implementation.
final tutorsRepositoryProvider = Provider<TutorsRepository>(
  (ref) => throw UnimplementedError(
    'tutorsRepositoryProvider must be overridden in ProviderScope.',
  ),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
// For `FutureProviderFamily` alone. The name of the provider's own type is the
// annotation below, and a record-typed family argument is one of the shapes the
// `specify_nonobvious_property_types` rule will not infer for itself. The family
// classes are not on `flutter_riverpod.dart`, so this is the library that has
// them.
import 'package:flutter_riverpod/misc.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';
import 'package:peerpass/features/matching/data/repositories/matching_repository.dart';

/// One search for tutors, as the pair of things that can change it.
///
/// A record rather than a class because it is only ever a cache key: two searches
/// with the same two fields are the same search, and value equality is what lets
/// the family reuse the first answer instead of asking again for a student who
/// toggled the widening switch back and forth.
typedef MatchQuery = ({String courseUnitId, bool widenToSubject});

/// The course units the picker offers.
///
/// Read here rather than reused from the auth feature. The dependency rules only
/// let one feature reach another through that feature's repository contract, and
/// a shared catalogue would need a home in `core/` that has no reason to know
/// what a course unit is.
final courseUnitOptionsProvider = FutureProvider<List<CourseUnit>>(
  (ref) => ref.watch(matchingRepositoryProvider).courseUnits(),
  retry: (retryCount, error) => null,
);

/// The tutors the API will propose for one query.
///
/// A family keyed by [MatchQuery], so the results screen, a re-search with
/// widening on, and a second unit in the same session are three separate
/// answers rather than one slot each overwriting the other. [AsyncValue] already
/// carries the three states the screen renders -- waiting, the answer, and the
/// reason there is none -- and a "nobody is eligible" answer is one of those
/// answers, not an error.
///
/// The automatic retry is off for the reason `sessionListProvider` switches it
/// off: a screen with a "Try again" button must not also be re-requesting behind
/// the user's finger. The button and the switch are the retry.
final FutureProviderFamily<MatchResult, MatchQuery> matchResultsProvider =
    FutureProvider.family<MatchResult, MatchQuery>(
      (ref, query) => ref
          .watch(matchingRepositoryProvider)
          .suggestions(
            courseUnitId: query.courseUnitId,
            widenToSubject: query.widenToSubject,
          ),
      retry: (retryCount, error) => null,
    );

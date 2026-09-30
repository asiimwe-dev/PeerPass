import 'package:flutter_riverpod/flutter_riverpod.dart';
// For the `*ProviderFamily` type names alone. The families below are annotated
// rather than left to inference because `specify_nonobvious_property_types` will
// not infer a family provider's own type for itself, and the alternative -- a
// suppression comment on the declaration -- leaves the type of the app's public
// providers unstated. The family classes are not on `flutter_riverpod.dart`, so
// this is the library that exports them.
import 'package:flutter_riverpod/misc.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/features/tutors/data/models/tutor_detail.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';
import 'package:peerpass/features/tutors/data/repositories/tutors_repository.dart';

/// The tutors the rail shows, most endorsed first.
///
/// An [AsyncNotifier] rather than a plain controller because the only thing to
/// do with the rail is load it, and [AsyncValue] already carries the three states
/// it has to render: loading, the entries, and the reason there are none. A
/// separate `loading` flag would be a second answer to a question the state
/// already answers, free to disagree with it.
///
/// A family keyed by course unit, nullable, because the unfiltered rail and the
/// rail narrowed to one unit are the same question asked two ways. Null is a
/// legitimate key rather than a special case: an unfiltered rail is what the
/// home screen shows, and it is what the API documents as the default.
///
/// The automatic retry is switched off for the reason `sessionListProvider`
/// switches it off: a screen that offers a "Try again" button must not also be
/// re-requesting underneath the user's finger. The button, and the pull to
/// refresh, are the retry.
final AsyncNotifierProviderFamily<
  TopTutorsNotifier,
  List<TutorRailEntry>,
  String?
>
topTutorsProvider = AsyncNotifierProvider.family<
  TopTutorsNotifier,
  List<TutorRailEntry>,
  String?
>(TopTutorsNotifier.new, retry: (retryCount, error) => null);

class TopTutorsNotifier extends AsyncNotifier<List<TutorRailEntry>> {
  TopTutorsNotifier(this.courseUnitId);

  /// The unit to narrow the rail to, or null for the whole university.
  final String? courseUnitId;

  @override
  Future<List<TutorRailEntry>> build() =>
      ref.read(tutorsRepositoryProvider).topTutors(courseUnitId: courseUnitId);
}

/// One tutor's profile, for the screen a rail card opens.
///
/// A family keyed by public id rather than one provider holding "the tutor being
/// looked at", because two of these can be alive at once -- a detail screen and
/// a shareable link to it -- and a single slot would make the second overwrite
/// the first one's state. Retried only by invalidating, for the reason above.
final AsyncNotifierProviderFamily<TutorDetailNotifier, TutorDetail, String>
tutorDetailProvider = AsyncNotifierProvider.family<
  TutorDetailNotifier,
  TutorDetail,
  String>(TutorDetailNotifier.new, retry: (retryCount, error) => null);

class TutorDetailNotifier extends AsyncNotifier<TutorDetail> {
  TutorDetailNotifier(this.userId);

  final String userId;

  @override
  Future<TutorDetail> build() =>
      ref.read(tutorsRepositoryProvider).tutor(userId);
}

/// The course units, so an endorsed id on the detail screen can be named.
///
/// Read by this feature rather than shared with the matching picker. The
/// dependency rules only let one feature reach another's repository contract,
/// and a catalogue HTTP call has nowhere in `core/` to live that would not be a
/// new convention. Ten duplicated lines is the cheaper of the two.
final courseUnitCatalogueProvider = FutureProvider<List<CourseUnit>>(
  (ref) => ref.watch(tutorsRepositoryProvider).courseUnits(),
  retry: (retryCount, error) => null,
);

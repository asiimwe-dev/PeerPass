import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/features/tutors/data/models/tutor_detail.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';
import 'package:peerpass/features/tutors/data/repositories/tutors_repository.dart';

/// In-memory stand-in for the tutor discovery endpoints.
///
/// What widget tests resolve, because a widget test has no server to talk to. It
/// implements the repository's shape rather than the datasource's, because that
/// is the seam a test cares about: overriding the repository is the only
/// composition the app supports.
///
/// A fake and not a stub, in the two places it matters: an unknown tutor really
/// 404s rather than returning a blank profile, and a rail filtered on a unit
/// really comes back short instead of returning everything. A stub that ignored
/// its argument would let a screen that renders the wrong set pass.
class FakeTutorsRepository implements TutorsRepository {
  FakeTutorsRepository({
    List<TutorRailEntry> tutors = const [],
    List<TutorDetail> profiles = const [],
    List<CourseUnit> courseUnits = const [],
  }) : _tutors = List<TutorRailEntry>.of(tutors),
       _profiles = List<TutorDetail>.of(profiles),
       _courseUnits = List<CourseUnit>.of(courseUnits);

  final List<TutorRailEntry> _tutors;
  final List<TutorDetail> _profiles;
  final List<CourseUnit> _courseUnits;

  /// The course units the detail screen resolves endorsed ids against.
  List<CourseUnit> get catalogue => List<CourseUnit>.unmodifiable(_courseUnits);

  /// The `courseUnitId` values the rail was filtered by, in order.
  ///
  /// Kept so a test can prove the rail narrowed rather than being handed the
  /// whole list by a screen that ignored its input.
  final List<String?> railFilters = [];

  @override
  Future<List<TutorRailEntry>> topTutors({String? courseUnitId}) async {
    railFilters.add(courseUnitId);
    if (courseUnitId == null) return List<TutorRailEntry>.unmodifiable(_tutors);

    // Approximated with the endorsements the fake knows about. The real filter is
    // the API's competency gate for the unit, which this client cannot evaluate
    // and is not the place to start.
    return [
      for (final entry in _tutors)
        if (entry.endorsedCourseUnitIds.contains(courseUnitId)) entry,
    ];
  }

  @override
  Future<TutorDetail> tutor(String userId) async {
    for (final profile in _profiles) {
      if (profile.profile.userId == userId) return profile;
    }

    // A rail entry without its own profile becomes one, so a test that only
    // cares about the rail does not have to write the same tutor twice.
    for (final entry in _tutors) {
      if (entry.tutor.userId != userId) continue;
      return TutorDetail(
        profile: entry.tutor,
        endorsedCourseUnitIds: entry.endorsedCourseUnitIds,
        endorsementCount: entry.endorsementCount,
      );
    }

    // The API answers a non-tutor and a non-existent user identically, and so
    // does this: a student must not be able to learn which accounts hold the
    // tutor role from the shape of the refusal.
    throw const NotFoundFailure('That tutor could not be found.');
  }

  @override
  Future<List<CourseUnit>> courseUnits({String? universityId}) async =>
      List<CourseUnit>.unmodifiable(_courseUnits);
}

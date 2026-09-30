import 'package:dio/dio.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/core/network/network_exceptions.dart';
import 'package:peerpass/features/tutors/data/datasources/remote_tutors_datasource.dart';
import 'package:peerpass/features/tutors/data/models/tutor_detail.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';
import 'package:peerpass/features/tutors/data/repositories/tutors_repository.dart';

/// [TutorsRepository] over the real API.
///
/// The only layer that knows both the wire format and the failure hierarchy. The
/// `_guard` helper below is the third copy of the one in
/// `remote_auth_repository.dart` and `remote_sessions_repository.dart`,
/// duplicated rather than lifted into `core/`: hoisting it means editing files
/// this feature does not own. Hoisting it is still the right call, and this
/// being the third is the note that it is now overdue.
class RemoteTutorsRepository implements TutorsRepository {
  const RemoteTutorsRepository(this._remote);

  final RemoteTutorsDatasource _remote;

  @override
  Future<List<TutorRailEntry>> topTutors({String? courseUnitId}) {
    // The whole body is inside the guard, including the parse. A malformed
    // response is a server fault, and a `fromJson` that ran after the guard
    // returned would throw past every translation here and reach the screen as
    // a bare `FormatException`.
    return _guard(() async {
      final bodies = await _remote.topTutors(courseUnitId: courseUnitId);
      return bodies.map(TutorRailEntry.fromJson).toList();
    });
  }

  @override
  Future<TutorDetail> tutor(String userId) =>
      _guard(() async => TutorDetail.fromJson(await _remote.tutor(userId)));

  @override
  Future<List<CourseUnit>> courseUnits({String? universityId}) =>
      _guard(() => _remote.courseUnits(universityId: universityId));

  /// Runs a call and translates whatever comes back into a [Failure].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Object catch (error) {
      throw _toFailure(error);
    }
  }

  Failure _toFailure(Object error) {
    if (error is Failure) return error;
    if (error is FormatException) {
      // The API answered with something that is not the shape it documents.
      return const ServerFailure(
        'The server sent something we could not read.',
      );
    }
    if (error is DioException) return mapDioException(error);
    return const UnknownFailure();
  }
}

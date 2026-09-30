import 'package:dio/dio.dart';
import 'package:peerpass/core/models/course_unit.dart';

/// Talks to the `/v1/tutors` endpoints and the course-unit catalogue.
///
/// Throws [DioException], not a `Failure`. Classification belongs to
/// `core/network/network_exceptions.dart` and happens once, in the repository,
/// so a socket error and an RFC 9457 problem document are translated by the same
/// code whichever endpoint produced them. Bodies come back as raw JSON on
/// purpose: the repository is where the wire shape becomes a model, so there is
/// one place to look when the two disagree.
class RemoteTutorsDatasource {
  const RemoteTutorsDatasource(this._dio);

  final Dio _dio;

  /// The discovery rail.
  ///
  /// [courseUnitId] narrows the rail to tutors who pass the competency gate in
  /// that unit. It is left out of the query entirely when null rather than sent
  /// as an empty string, so "no filter" is visibly different from "a filter
  /// that matched nothing" in the request the API receives.
  ///
  /// No `limit` is sent. The API's default of ten is the rail length, and a
  /// client that hardcoded the number would be a second place it is decided --
  /// changing it on the server would then change the app's idea of a rail for
  /// some accounts and not others.
  ///
  /// A well-formed `course_unit_id` that names no unit answers `[]`. That is not
  /// a failure to be handled here: the API answers an unknown or foreign unit
  /// with an empty list precisely so a client that filtered on a stale picker
  /// value does not get an error screen.
  Future<List<Map<String, dynamic>>> topTutors({String? courseUnitId}) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/tutors/top',
      queryParameters: {'course_unit_id': ?courseUnitId},
    );
    return (response.data ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// One tutor, by public id.
  ///
  /// 404 for a user who does not exist and for one who is not a tutor, which the
  /// repository turns into the same `NotFoundFailure` either way.
  Future<Map<String, dynamic>> tutor(String userId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/tutors/$userId',
    );
    return response.data!;
  }

  /// The course units a tutor's endorsements are recorded against.
  ///
  /// Read here so the detail screen can put a name on an endorsed unit. The API
  /// sends endorsement *ids* and nothing else that identifies them, and a card
  /// listing five uuids is not a card a student can read.
  ///
  /// This is the same endpoint onboarding reads, and it is deliberately a second
  /// call rather than a shared datasource: the dependency rules permit a feature
  /// to reach another feature only through that feature's repository contract,
  /// so a datasource shared by two features would need a home outside `features/`
  /// and a new place in `core/` to hold an HTTP call about course units. Ten
  /// duplicated lines beat that.
  Future<List<CourseUnit>> courseUnits({String? universityId}) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/academics/course-units',
      queryParameters: {'university_id': ?universityId},
    );
    return [
      for (final row in response.data ?? const <dynamic>[])
        CourseUnit(
          publicId: (row as Map<String, dynamic>)['id'] as String,
          code: row['code'] as String,
          name: row['name'] as String,
        ),
    ];
  }
}

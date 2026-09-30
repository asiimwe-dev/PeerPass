import 'package:dio/dio.dart';
import 'package:peerpass/core/models/course_unit.dart';

/// Talks to `/v1/matching` and reads the course-unit catalogue the picker offers.
///
/// Throws [DioException], not a `Failure`. Classification belongs to
/// `core/network/network_exceptions.dart` and happens once, in the repository,
/// so a socket error and an RFC 9457 problem document are translated by the same
/// code whichever endpoint produced them.
class RemoteMatchingDatasource {
  const RemoteMatchingDatasource(this._dio);

  final Dio _dio;

  /// The course units a student can pick, for their own university.
  ///
  /// Read here rather than reused from the auth feature's academics datasource.
  /// The dependency rules let one feature reach another only through that
  /// feature's repository contract, so a datasource shared by two features would
  /// need a home outside `features/` -- and `core/` is not where an HTTP call
  /// about course units belongs. The same endpoint is called twice in the app's
  /// life, once per flow, and the duplication is the cheaper of the two.
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

  /// Asks who may take this course unit.
  ///
  /// The unit-only route. The request-backed one, `/help-requests/{id}/matches`,
  /// answers about a help request the caller owns and would make the caller
  /// create one first; this client sends the unit it was given, and the response
  /// comes back with `request_id` null because nothing backs the query.
  ///
  /// Three fields, exactly. `MatchRequest` is a `RequestSchema`, which forbids
  /// unknown keys: sending a `request_id` the client did not receive, or any
  /// other extra, is a 422 rather than something ignored. [limit] is left at the
  /// API's own bound unless a caller asks for fewer, so "as many as the platform
  /// will propose" is decided in one place.
  Future<Map<String, dynamic>> suggestions({
    required String courseUnitId,
    required bool widenToSubject,
    int? limit,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/matching/suggestions',
      data: <String, dynamic>{
        'course_unit_id': courseUnitId,
        'widen_to_subject': widenToSubject,
        'limit': ?limit,
      },
    );
    return response.data!;
  }
}

import 'package:dio/dio.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/core/storage/session_cache.dart';

/// Talks to the `/v1/tutors` endpoints and the course-unit catalogue.
///
/// Throws [DioException], not a `Failure`. Classification belongs to
/// `core/network/network_exceptions.dart` and happens once, in the repository,
/// so a socket error and an RFC 9457 problem document are translated by the same
/// code whichever endpoint produced them. Bodies come back as raw JSON on
/// purpose: the repository is where the wire shape becomes a model, so there is
/// one place to look when the two disagree.
class RemoteTutorsDatasource {
  const RemoteTutorsDatasource(this._dio, {this.cache});

  final Dio _dio;

  /// The last successful rail, so home is not empty when the API is not reachable.
  final SessionCache? cache;

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
    // Captured before the request so a response that arrives after an account
    // change cannot be written into the next account's namespace.
    final accountId = cache?.accountId;
    try {
      final response = await _dio.get<List<dynamic>>(
        '/v1/tutors/top',
        queryParameters: {'course_unit_id': ?courseUnitId},
      );
      final tutors = (response.data ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      await cache?.writeTopTutors(
        tutors,
        courseUnitId: courseUnitId,
        accountId: accountId,
      );
      return tutors;
    } on DioException catch (error) {
      if (!_canUseCache(error)) rethrow;
      final cached = await cache?.readTopTutors(
        courseUnitId: courseUnitId,
        accountId: accountId,
      );
      if (cached != null) {
        return [
          for (final row in cached) {...row, '_offline_cached': true},
        ];
      }
      rethrow;
    }
  }

  /// Whether a transport failure is one a saved answer can stand in for.
  ///
  /// Only a connection that never reached the server. A `500`, a `401`, or a
  /// malformed body is the server answering, and showing yesterday's tutors over
  /// that would hide the one fact the screen needs to report.
  bool _canUseCache(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;

  /// The caller's own tutor dashboard.
  ///
  /// No path parameter, because the API only answers about the authenticated
  /// tutor. A caller without a tutor profile is a normal 200 whose body says so;
  /// it is not a 404 and the screen renders it as a next step rather than an
  /// error.
  Future<Map<String, dynamic>> myHq() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/tutors/me');
    return response.data!;
  }

  /// Turns the caller's availability on or off.
  ///
  /// The whole updated dashboard comes back, so the screen does not have to
  /// merge a local flag into stale counters after a successful save.
  ///
  /// The flag is positional because the repository contract fixes it that way;
  /// at the two call sites `setAcceptingRequests(false)` reads as clearly as a
  /// named argument would.
  // ignore: avoid_positional_boolean_parameters
  Future<Map<String, dynamic>> setAcceptingRequests(bool accepting) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/v1/tutors/me',
      data: {'accepting_requests': accepting},
    );
    return response.data!;
  }

  /// One tutor, by public id.
  ///
  /// 404 for a user who does not exist and for one who is not a tutor, which the
  /// repository turns into the same `NotFoundFailure` either way.
  Future<Map<String, dynamic>> tutor(String userId) async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/tutors/$userId');
    return response.data!;
  }

  /// What other students said about one tutor, newest first.
  ///
  /// A page size rather than a pager. The profile shows the newest handful and
  /// the rating count beside it says how much evidence is behind them; there is
  /// no offset to send because the API does not offer one.
  Future<List<Map<String, dynamic>>> reviews(
    String userId, {
    int? limit,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/tutors/$userId/reviews',
      queryParameters: {'limit': ?limit},
    );
    return (response.data ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
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

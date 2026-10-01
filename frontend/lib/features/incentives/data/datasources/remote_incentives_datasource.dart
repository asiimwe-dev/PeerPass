import 'package:dio/dio.dart';

/// Talks to the `/v1/incentives` endpoints.
///
/// Throws [DioException], not a `Failure`. Classification belongs to
/// `core/network/network_exceptions.dart` and happens once, in the repository,
/// so a socket error and an RFC 9457 problem document are translated by the same
/// code whichever endpoint produced them. The body comes back as raw JSON on
/// purpose: the repository is where the wire shape becomes a model, so there is
/// one place to look when the two disagree.
class RemoteIncentivesDatasource {
  const RemoteIncentivesDatasource(this._dio);

  final Dio _dio;

  /// The caller's own certificate eligibility.
  ///
  /// No path parameter and no query parameter, because the API answers only
  /// about the authenticated caller and there is nothing a client could send to
  /// ask about anyone else. A user id in the path would be a second, unguarded
  /// way to read a tutor's hours.
  Future<Map<String, dynamic>> myCertificate() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/incentives/certificate',
    );
    return response.data!;
  }
}

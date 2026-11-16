import 'package:dio/dio.dart';

/// Talks to `/v1/sessions/{id}/messages`.
///
/// Throws [DioException], not a `Failure`: classification happens once, in the
/// repository, so a socket error and an RFC 9457 problem document are translated
/// by the same code on every feature. Bodies come back as raw JSON so the
/// repository is the one place where the wire shape becomes a model.
class RemoteMessagesDatasource {
  const RemoteMessagesDatasource(this._dio);

  final Dio _dio;

  /// The thread, oldest first, or only what came after [after].
  ///
  /// `after` is the public id of the last message the client holds, not a
  /// timestamp: two messages can share a second, and a cursor that compared
  /// clocks would either skip one or repeat one forever. The API compares the
  /// pair behind the id.
  Future<List<Map<String, dynamic>>> messages(
    String sessionId, {
    String? after,
    int limit = 50,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/sessions/$sessionId/messages',
      queryParameters: <String, dynamic>{
        'limit': limit,
        'after': ?after,
      },
    );
    return (response.data ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Adds one message, returning the row as stored.
  ///
  /// No recipient is sent: the session names both parties and the token says
  /// which one is writing, so a body that could name someone else would be a way
  /// to write outside the match.
  Future<Map<String, dynamic>> send(String sessionId, String body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/sessions/$sessionId/messages',
      data: <String, dynamic>{'body': body},
    );
    return response.data!;
  }

  /// Marks what the other party wrote as read, returning how many rows changed.
  Future<int> markRead(String sessionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/sessions/$sessionId/messages/read',
    );
    return (response.data?['marked'] as num?)?.toInt() ?? 0;
  }
}

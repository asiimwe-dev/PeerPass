import 'package:dio/dio.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/network/network_exceptions.dart';
import 'package:peerpass/features/messages/data/datasources/remote_messages_datasource.dart';
import 'package:peerpass/features/messages/data/models/session_message.dart';
import 'package:peerpass/features/messages/data/repositories/messages_repository.dart';

/// [MessagesRepository] over the real API.
///
/// The third copy of this `_guard`, and still duplicated rather than hoisted:
/// two features already carry it, and lifting it into `core/network/` in the
/// middle of a feature is a refactor nobody asked for. When a fourth appears,
/// it moves.
class RemoteMessagesRepository implements MessagesRepository {
  const RemoteMessagesRepository(this._remote);

  final RemoteMessagesDatasource _remote;

  @override
  Future<List<SessionMessage>> messages(String sessionId, {String? after}) {
    // The parse is inside the guard so a malformed row is reported as a server
    // fault instead of escaping as a bare `FormatException`.
    return _guard(() async {
      final rows = await _remote.messages(sessionId, after: after);
      return rows.map(SessionMessage.fromJson).toList();
    });
  }

  @override
  Future<SessionMessage> send({
    required String sessionId,
    required String body,
  }) {
    return _guard(
      () async =>
          SessionMessage.fromJson(await _remote.send(sessionId, body)),
    );
  }

  @override
  Future<int> markRead({required String sessionId}) =>
      _guard(() => _remote.markRead(sessionId));

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
      return const ServerFailure(
        'The server sent something we could not read.',
      );
    }
    if (error is DioException) return mapDioException(error);
    return const UnknownFailure();
  }
}

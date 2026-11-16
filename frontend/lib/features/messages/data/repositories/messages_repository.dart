import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/messages/data/models/session_message.dart';

/// The conversation contract the chat screen depends on.
///
/// Every method throws a [Failure], never a transport exception and never a
/// `FormatException`. The implementation is where a `DioException`, a problem
/// document and an unreadable body become a message the screen can render.
///
/// There is no method to start a conversation and none to list conversations.
/// A thread is the session: it exists the moment the tutor accepts a request,
/// and the sessions list is where a person finds it. Adding either method here
/// would be the first step towards a chat with people the app never matched.
abstract interface class MessagesRepository {
  /// The thread, oldest first.
  ///
  /// [after] is the public id of the last message the caller already holds, and
  /// returns only what arrived since. Null asks for the newest page.
  Future<List<SessionMessage>> messages(String sessionId, {String? after});

  /// Sends one message, returning it as the server stored it.
  ///
  /// The body is the message itself; trimming and the length limit are the
  /// server's, because a client that trimmed differently would disagree with the
  /// copy the other party reads.
  Future<SessionMessage> send({required String sessionId, required String body});

  /// Marks the other party's messages in this thread read.
  ///
  /// Returns how many were actually unread, so the screen can tell a cleared
  /// badge from one that was already clear.
  Future<int> markRead({required String sessionId});
}

/// The messages contract, as a live instance.
///
/// Throws unless overridden, for the same reason the other repository providers
/// do: a missing wiring in `main.dart` should fail at the first screen that needs
/// it rather than silently browse an empty inbox.
final messagesRepositoryProvider = Provider<MessagesRepository>(
  (ref) => throw UnimplementedError(
    'messagesRepositoryProvider must be overridden in ProviderScope.',
  ),
);

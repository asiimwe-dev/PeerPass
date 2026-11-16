import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/messages/data/models/session_message.dart';
import 'package:peerpass/features/messages/data/repositories/messages_repository.dart';

/// In-memory stand-in for the session message endpoints.
///
/// A fake and not a stub: sending appends a row, reading marks only the other
/// party's rows, and a failure it is told to produce is thrown as the [Failure]
/// the real repository would throw. A fake that accepted everything would let a
/// screen that never shows a refusal pass.
class FakeMessagesRepository implements MessagesRepository {
  FakeMessagesRepository({List<SessionMessage> messages = const []})
    : _messages = List<SessionMessage>.of(messages);

  final List<SessionMessage> _messages;

  /// The signed-in user, as the server reads it from the access token.
  ///
  /// Sending needs to know who wrote a row, and the interface deliberately
  /// carries no user id: the real API takes it from the token. A test sets this
  /// through the same pump helper that signs the account in.
  String? currentUserId;

  /// When set, [send] throws it instead of appending.
  Failure? sendFailure;

  /// When set, [messages] throws it instead of answering.
  Failure? listFailure;

  /// When set, [markRead] throws it instead of clearing.
  Failure? readFailure;

  int _counter = 0;

  /// Every thread read, as the cursor it was asked for.
  final List<String?> readCursors = [];

  /// Every body passed to [send], in order.
  final List<String> sentBodies = [];

  /// Every session id passed to [markRead], in order.
  final List<String> markedReadSessionIds = [];

  /// The rows this fake holds, for a test that needs to arrange one.
  List<SessionMessage> get storedMessages =>
      List<SessionMessage>.unmodifiable(_messages);

  /// Queues a message the other party wrote, as the next poll would find it.
  ///
  /// The chat is pushless: the other side's message arrives when the client asks
  /// again. A test drives that by adding the row here and letting the poll timer
  /// fire, rather than by calling the controller directly, so the poll path is
  /// the one under test.
  SessionMessage deliver({
    required String sessionId,
    required String senderId,
    required String body,
  }) {
    final message = SessionMessage(
      id: 'server-${++_counter}',
      sessionId: sessionId,
      senderId: senderId,
      body: body,
      createdAt: _nextTimestamp(),
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<List<SessionMessage>> messages(String sessionId, {String? after}) async {
    readCursors.add(after);
    if (listFailure case final failure?) throw failure;

    final thread = [
      for (final message in _messages)
        if (message.sessionId == sessionId) message,
    ];
    if (after == null) return thread;

    final index = thread.indexWhere((message) => message.id == after);
    // A cursor this fake does not hold answers with everything, which is what a
    // client that lost its place should see: newer rows, not silence.
    if (index == -1) return thread;
    return thread.sublist(index + 1);
  }

  @override
  Future<SessionMessage> send({
    required String sessionId,
    required String body,
  }) async {
    sentBodies.add(body);
    if (sendFailure case final failure?) throw failure;

    final viewerId = currentUserId;
    if (viewerId == null) {
      throw const AuthFailure();
    }
    final message = SessionMessage(
      id: 'sent-${++_counter}',
      sessionId: sessionId,
      senderId: viewerId,
      body: body,
      createdAt: _nextTimestamp(),
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<int> markRead({required String sessionId}) async {
    markedReadSessionIds.add(sessionId);
    if (readFailure case final failure?) throw failure;

    var marked = 0;
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      if (message.sessionId != sessionId) continue;
      if (message.senderId == currentUserId) continue;
      if (message.readAt != null) continue;
      _messages[index] = SessionMessage(
        id: message.id,
        sessionId: message.sessionId,
        senderId: message.senderId,
        body: message.body,
        createdAt: message.createdAt,
        readAt: _nextTimestamp(),
      );
      marked++;
    }
    return marked;
  }

  /// A clock that only moves forward, so two messages sent in the same
  /// millisecond still have a stable order.
  DateTime _nextTimestamp() =>
      DateTime.utc(2026, 2).add(Duration(minutes: _counter));
}

import 'package:flutter/foundation.dart';

/// One message in a session's thread, as the API returns it.
///
/// A wire DTO. It knows which party wrote it, which is the one question a bubble
/// needs to answer, but not who the reader is: that is the session's job, and
/// the bubble is told.
///
/// The parse rule is the same as the rest of the data layer's. Missing `id`,
/// `session_id`, `sender_id`, `body` or `created_at` is a [FormatException],
/// because a bubble with no sender or no time is not a message a screen can
/// draw. A missing `read_at` is not a fault: it is the ordinary state of a
/// message nobody has opened yet.
@immutable
class SessionMessage {
  const SessionMessage({
    required this.id,
    required this.sessionId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory SessionMessage.fromJson(Map<String, dynamic> json) {
    final id = _readString(json, 'id');
    final sessionId = _readString(json, 'session_id');
    final senderId = _readString(json, 'sender_id');
    final body = json['body'];
    final createdAtWire = json['created_at'];

    if (id == null ||
        sessionId == null ||
        senderId == null ||
        body is! String ||
        createdAtWire is! String) {
      throw const FormatException('A message is missing a required field.');
    }

    final createdAt = DateTime.tryParse(createdAtWire);
    if (createdAt == null) {
      throw const FormatException('A message has an invalid timestamp.');
    }

    DateTime? readAt;
    final readAtWire = json['read_at'];
    if (readAtWire != null) {
      if (readAtWire is! String) {
        throw const FormatException('A message has an invalid read time.');
      }
      readAt = DateTime.tryParse(readAtWire);
      if (readAt == null) {
        throw const FormatException('A message has an invalid read time.');
      }
    }

    return SessionMessage(
      id: id,
      sessionId: sessionId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      readAt: readAt,
    );
  }

  final String id;

  final String sessionId;

  /// The public id of whoever wrote this, which is always one of the session's
  /// two parties.
  final String senderId;

  final String body;

  final DateTime createdAt;

  /// When the other party read it, or null while it is still unread.
  ///
  /// Null on one's own message is not "unread by me": the client does not track
  /// its own reading, and the reader is whoever the session says wrote the other
  /// half.
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// Whether [viewerId] wrote this message.
  ///
  /// A comparison and not a stored flag, because the same row is read by both
  /// parties and there is no field that could be correct for both.
  bool isMine(String? viewerId) => viewerId != null && senderId == viewerId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionMessage &&
          other.id == id &&
          other.sessionId == sessionId &&
          other.senderId == senderId &&
          other.body == body &&
          other.createdAt == createdAt &&
          other.readAt == readAt;

  @override
  int get hashCode =>
      Object.hash(id, sessionId, senderId, body, createdAt, readAt);

  @override
  String toString() => 'SessionMessage($id, $senderId)';
}

/// A public id, or null when the field is absent or not a usable string.
String? _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) return null;
  return value;
}

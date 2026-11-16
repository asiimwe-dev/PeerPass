import 'package:flutter/foundation.dart';

/// Why a notification exists, as the client switches on it.
///
/// The wire value is held separately from the Dart name for the same reason the
/// session status does it: renaming a case must not silently change what the
/// server sends. The backend's enum is the source of truth, and a value this
/// build has never heard of becomes [unknown] rather than throwing, because a
/// notification about a new event is still a notification a student can read.
enum AppNotificationType {
  requestReceived('request_received'),
  requestAccepted('request_accepted'),
  requestDeclined('request_declined'),
  sessionStarted('session_started'),
  sessionCompleted('session_completed'),
  sessionCancelled('session_cancelled'),
  ratingReceived('rating_received'),
  promotion('promotion'),
  messageReceived('message_received'),

  /// A type this build does not know.
  ///
  /// Client-only; the API never sends it. Kept distinct from a parse failure so
  /// an older APK can still show the title and body of a newer event instead of
  /// dropping it on the floor.
  unknown('');

  AppNotificationType(this.wireValue);

  /// The value the API uses on the wire.
  final String wireValue;

  /// The type named by [value], or [unknown].
  static AppNotificationType fromWire(String value) {
    for (final type in values) {
      if (type != unknown && type.wireValue == value) return type;
    }
    return unknown;
  }
}

/// One row in the signed-in user's inbox.
///
/// A wire DTO. It carries no decision about where a tap leads: that depends on
/// the route table in the presentation layer, and putting a path here would make
/// the model depend on navigation. What it does expose is the identity of the
/// event (`sessionId`, `requestId`) so the screen can name the right destination
/// without re-parsing the raw map.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.typeWire,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const <String, String>{},
    this.readAt,
  });

  /// Reads one row from the wire.
  ///
  /// The rule is the same as the session model's: a field the screen cannot
  /// render without is a [FormatException], and a field with an obvious neutral
  /// reading is defaulted. A notification without an id, a type, a title, a body
  /// or a creation time is a broken response, not an empty state. `read_at` null
  /// genuinely means unread, and `data` missing means the event has nothing to
  /// open.
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final typeWire = json['type'];
    final title = json['title'];
    final body = json['body'];
    final createdAtWire = json['created_at'];

    if (id is! String ||
        id.isEmpty ||
        typeWire is! String ||
        typeWire.isEmpty ||
        title is! String ||
        body is! String ||
        createdAtWire is! String) {
      throw const FormatException(
        'A notification is missing a required field.',
      );
    }

    final createdAt = DateTime.tryParse(createdAtWire);
    if (createdAt == null) {
      throw const FormatException('A notification has an invalid timestamp.');
    }

    final readAtWire = json['read_at'];
    DateTime? readAt;
    if (readAtWire != null) {
      if (readAtWire is! String) {
        throw const FormatException('A notification has an invalid read time.');
      }
      readAt = DateTime.tryParse(readAtWire);
      if (readAt == null) {
        throw const FormatException('A notification has an invalid read time.');
      }
    }

    return AppNotification(
      id: id,
      typeWire: typeWire,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: readAt,
      data: _stringMap(json['data']),
    );
  }

  final String id;

  /// The type exactly as the API sent it.
  final String typeWire;

  final String title;
  final String body;

  /// Public ids and a `kind` for the screen that opens from this row.
  final Map<String, String> data;

  /// When the owner first opened this notification, or null while unread.
  final DateTime? readAt;

  final DateTime createdAt;

  /// The parsed type, or [AppNotificationType.unknown].
  AppNotificationType get type => AppNotificationType.fromWire(typeWire);

  bool get isUnread => readAt == null;

  /// The session this notification is about, when it names one.
  String? get sessionId => data['session_id'];

  /// The help request this notification is about, when it names one.
  String? get requestId => data['request_id'];

  /// The same notification after its owner read it.
  AppNotification markedRead(DateTime at) {
    if (readAt != null) return this;
    return AppNotification(
      id: id,
      typeWire: typeWire,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: at,
      data: data,
    );
  }

  /// Values are strings on the wire; a non-string value is dropped rather than
  /// stringified, because the screen uses them as opaque ids and a fabricated
  /// `"null"` is worse than a missing destination.
  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final values = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) values[key] = value;
    }
    return Map<String, String>.unmodifiable(values);
  }
}

/// One page of the inbox.
///
/// Offset paging rather than `Paginated`'s page numbering, because the API's
/// envelope is offset-based and its `has_more` is `offset + len(items) < total`.
/// Recomputing that from a page number would disagree on a partial page, which
/// is exactly the page a "load older" button is shown on.
@immutable
class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final total = json['total'];
    final limit = json['limit'];
    final offset = json['offset'];

    if (rawItems is! List || total is! int || limit is! int || offset is! int) {
      throw const FormatException('A notification page is malformed.');
    }

    final items = <AppNotification>[
      for (final row in rawItems)
        if (row is Map<String, dynamic>)
          AppNotification.fromJson(row)
        else
          throw const FormatException('A notification row is malformed.'),
    ];

    final hasMoreWire = json['has_more'];

    return NotificationPage(
      items: List<AppNotification>.unmodifiable(items),
      total: total,
      limit: limit,
      offset: offset,
      // The server's answer when it gives one, and the documented derivation
      // when it does not. Both say the same thing for an intact response.
      hasMore: hasMoreWire is bool
          ? hasMoreWire
          : offset + items.length < total,
    );
  }

  final List<AppNotification> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;
}

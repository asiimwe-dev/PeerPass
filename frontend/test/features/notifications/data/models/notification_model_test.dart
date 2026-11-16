import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/notifications/data/models/notification_model.dart';

Map<String, dynamic> _row({
  Object? id = 'notification-1',
  Object? type = 'request_received',
  Object? title = 'New tutoring request',
  Object? body = 'A student needs help.',
  Object? data = const {'kind': 'help_request', 'request_id': 'request-1'},
  Object? readAt,
  Object? createdAt = '2026-11-03T09:00:00Z',
}) {
  return {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'data': data,
    'read_at': readAt,
    'created_at': createdAt,
  };
}

void main() {
  group('AppNotification', () {
    test('reads the row the API documents', () {
      final notification = AppNotification.fromJson(_row());

      expect(notification.id, 'notification-1');
      expect(notification.type, AppNotificationType.requestReceived);
      expect(notification.title, 'New tutoring request');
      expect(notification.body, 'A student needs help.');
      expect(notification.data, {
        'kind': 'help_request',
        'request_id': 'request-1',
      });
      expect(notification.isUnread, isTrue);
      expect(notification.requestId, 'request-1');
      expect(notification.sessionId, isNull);
      expect(notification.createdAt, DateTime.utc(2026, 11, 3, 9));
    });

    test('a read row carries the time it was read', () {
      final notification = AppNotification.fromJson(
        _row(readAt: '2026-11-03T10:00:00Z'),
      );

      expect(notification.isUnread, isFalse);
      expect(notification.readAt, DateTime.utc(2026, 11, 3, 10));
    });

    test('a message notification keeps its session id', () {
      // The wire value is the contract; the enum name is not. A server that sends
      // `message_received` must reach the chat path, not `unknown`.
      final row = AppNotification.fromJson(
        _row(
          type: 'message_received',
          data: {'kind': 'session', 'session_id': 'session-1'},
        ),
      );

      expect(row.type, AppNotificationType.messageReceived);
      expect(row.sessionId, 'session-1');
    });

    test('a type this build has never heard of is still readable', () {
      // The point is forward compatibility: a newer backend must not make an
      // older APK drop the message or crash the list. The row is shown and its
      // unknown type simply has no destination.
      final notification = AppNotification.fromJson(
        _row(type: 'certificate_earned'),
      );

      expect(notification.type, AppNotificationType.unknown);
      expect(notification.typeWire, 'certificate_earned');
      expect(notification.title, 'New tutoring request');
    });

    test('a missing required field is a broken body, not an empty state', () {
      for (final field in ['id', 'type', 'title', 'body', 'created_at']) {
        final row = _row()..[field] = null;

        expect(
          () => AppNotification.fromJson(row),
          throwsFormatException,
          reason: 'a missing $field must not become an unrenderable row',
        );
      }
    });

    test('an unparseable timestamp is rejected rather than guessed', () {
      expect(
        () => AppNotification.fromJson(_row(createdAt: 'yesterday')),
        throwsFormatException,
      );
      expect(
        () => AppNotification.fromJson(_row(readAt: 'not a date')),
        throwsFormatException,
      );
    });

    test('non-string data values are dropped instead of stringified', () {
      // The screen uses these as opaque ids. A fabricated "42" is worse than a
      // missing destination because it sends the student to a screen that does
      // not exist.
      final notification = AppNotification.fromJson(
        _row(data: {'session_id': 'session-1', 'attempt': 42, 'ok': 'yes'}),
      );

      expect(notification.data, {'session_id': 'session-1', 'ok': 'yes'});
      expect(notification.sessionId, 'session-1');
    });

    test('marking read changes the row once', () {
      final notification = AppNotification.fromJson(_row());
      final at = DateTime.utc(2026, 11, 3, 11);

      final read = notification.markedRead(at);

      expect(
        notification.isUnread,
        isTrue,
        reason: 'the original is immutable',
      );
      expect(read.isUnread, isFalse);
      expect(read.readAt, at);
      expect(identical(read, notification), isFalse);

      final again = read.markedRead(DateTime.utc(2026, 11, 3, 12));
      expect(again.readAt, at, reason: 'the first read time is the one kept');
    });
  });

  group('NotificationPage', () {
    test('reads the API envelope and its own has_more answer', () {
      final page = NotificationPage.fromJson({
        'items': [_row(), _row(id: 'notification-2')],
        'total': 5,
        'limit': 2,
        'offset': 0,
        'has_more': true,
      });

      expect(page.items.map((n) => n.id), ['notification-1', 'notification-2']);
      expect(page.total, 5);
      expect(page.limit, 2);
      expect(page.offset, 0);
      expect(page.hasMore, isTrue);
    });

    test('derives has_more when the envelope omits it', () {
      final page = NotificationPage.fromJson({
        'items': [_row()],
        'total': 3,
        'limit': 1,
        'offset': 0,
      });

      // One row of three: a "load older" button is the honest next step.
      expect(page.hasMore, isTrue);

      final last = NotificationPage.fromJson({
        'items': [_row(id: 'notification-3')],
        'total': 3,
        'limit': 1,
        'offset': 2,
      });
      expect(last.hasMore, isFalse);
    });

    test('a malformed envelope is rejected', () {
      expect(
        () => NotificationPage.fromJson(const {'items': 'nope'}),
        throwsFormatException,
      );
      expect(
        () => NotificationPage.fromJson(const {
          'items': ['not a row'],
          'total': 1,
          'limit': 20,
          'offset': 0,
        }),
        throwsFormatException,
      );
    });
  });
}

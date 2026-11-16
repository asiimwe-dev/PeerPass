import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/features/notifications/data/models/notification_model.dart';
import 'package:peerpass/features/notifications/presentation/notification_links.dart';

import '../support.dart';

void main() {
  test('a new request opens the tutor request list', () {
    final row = notification(
      data: {'kind': 'help_request', 'request_id': 'request-1'},
    );

    expect(notificationRoute(row), AppRoutes.tutorRequests);
  });

  test('a decline opens matching so the student can choose again', () {
    final row = notification(
      type: AppNotificationType.requestDeclined,
      data: {'kind': 'help_request', 'request_id': 'request-1'},
    );

    expect(notificationRoute(row), AppRoutes.matching);
  });

  test('a booked session opens the session', () {
    final row = notification(
      type: AppNotificationType.requestAccepted,
      data: {'kind': 'session', 'session_id': 'session-1'},
    );

    expect(notificationRoute(row), AppRoutes.sessionDetailPath('session-1'));
  });

  test('a live or cancelled session opens the session', () {
    for (final type in [
      AppNotificationType.sessionStarted,
      AppNotificationType.sessionCancelled,
    ]) {
      final row = notification(
        type: type,
        data: {'kind': 'session', 'session_id': 'session-1'},
      );

      expect(notificationRoute(row), AppRoutes.sessionDetailPath('session-1'));
    }
  });

  test('a completed session opens the rating form it asks for', () {
    final row = notification(
      type: AppNotificationType.sessionCompleted,
      data: {'kind': 'session', 'session_id': 'session-1'},
    );

    expect(notificationRoute(row), AppRoutes.rateSessionPath('session-1'));
  });

  test('a received rating opens the session where feedback lives', () {
    // The recipient is the tutor, so the rating form -- which the tutee fills in
    // -- would be the wrong screen. The feedback is read on the session.
    final row = notification(
      type: AppNotificationType.ratingReceived,
      data: {'kind': 'rating', 'session_id': 'session-1', 'rating_id': 'r-1'},
    );

    expect(notificationRoute(row), AppRoutes.sessionDetailPath('session-1'));
  });

  test('a promotion opens the certificate screen', () {
    final row = notification(type: AppNotificationType.promotion);

    expect(notificationRoute(row), AppRoutes.certificate);
  });

  test('a message opens the thread it was written in', () {
    // Not the session screen behind the thread: a student who taps "new message"
    // and lands where the message is not visible would read that as the app
    // losing it.
    final row = notification(
      type: AppNotificationType.messageReceived,
      data: {'kind': 'session', 'session_id': 'session-1'},
    );

    expect(notificationRoute(row), AppRoutes.sessionChatPath('session-1'));
  });

  test('a row with no id opens nothing rather than guessing', () {
    for (final type in [
      AppNotificationType.requestAccepted,
      AppNotificationType.sessionStarted,
      AppNotificationType.sessionCompleted,
      AppNotificationType.sessionCancelled,
      AppNotificationType.ratingReceived,
      AppNotificationType.messageReceived,
    ]) {
      final row = notification(type: type);

      expect(notificationRoute(row), isNull, reason: '$type has no session id');
    }
  });

  test('an unknown type is shown but opens nothing', () {
    final row = notification(type: AppNotificationType.unknown);

    expect(notificationRoute(row), isNull);
  });
}

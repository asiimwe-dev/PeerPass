import 'package:peerpass/app/router.dart';
import 'package:peerpass/features/notifications/data/models/notification_model.dart';

/// Where tapping [notification] should lead, or null when it leads nowhere.
///
/// A switch over the parsed type rather than over `data['kind']`, because the
/// type is the thing the API guarantees and the kind is a hint the client could
/// have to tolerate missing. Each destination is the screen that answers the
/// notification's own sentence:
///
/// - a new request is answered on the tutor's request list;
/// - a decline is answered by choosing somebody else, so it opens matching;
/// - a completed session asks the tutee to rate it, so it opens the rating form;
/// - a received rating is read on the session it belongs to, because that is
///   where the tutor's feedback lives;
/// - a promotion is the certificate screen, which is where standing pays off.
///
/// Null rather than a guess when the ids are absent. Sending a student to a
/// screen that cannot name the thing they tapped is worse than leaving them in
/// the inbox, which at least still shows the message.
String? notificationRoute(AppNotification notification) {
  final sessionId = notification.sessionId;
  final sessionPath = sessionId == null
      ? null
      : AppRoutes.sessionDetailPath(sessionId);

  return switch (notification.type) {
    AppNotificationType.requestReceived => AppRoutes.tutorRequests,
    AppNotificationType.requestDeclined => AppRoutes.matching,
    AppNotificationType.requestAccepted ||
    AppNotificationType.sessionStarted ||
    AppNotificationType.sessionCancelled ||
    AppNotificationType.ratingReceived => sessionPath,
    // A message is answered in the thread it was written in, not on the session
    // behind it: opening a notification that says "new message" and landing on a
    // screen where the message is invisible would read as the app losing it.
    AppNotificationType.messageReceived =>
      sessionId == null ? null : AppRoutes.sessionChatPath(sessionId),
    AppNotificationType.sessionCompleted =>
      sessionId == null ? null : AppRoutes.rateSessionPath(sessionId),
    AppNotificationType.promotion => AppRoutes.certificate,
    // An older build reading a newer event: show the message, open nothing.
    AppNotificationType.unknown => null,
  };
}

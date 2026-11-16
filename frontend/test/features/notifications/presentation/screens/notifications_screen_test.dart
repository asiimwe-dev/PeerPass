import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/notifications/data/models/notification_model.dart';
import 'package:peerpass/features/notifications/data/repositories/fake_notifications_repository.dart';
import 'package:peerpass/features/notifications/data/repositories/notifications_repository.dart';
import 'package:peerpass/features/notifications/presentation/providers/notification_providers.dart';
import 'package:peerpass/features/notifications/presentation/screens/notifications_screen.dart';

import '../../support.dart';

ProviderContainer _container(NotificationsRepository repository) {
  final container = ProviderContainer(
    overrides: [notificationsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

/// A router that proves where a tap went without dragging in the whole app.
///
/// The destination routes print their own name, so an assertion is about the
/// path the inbox chose, not merely that some screen opened.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/sessions/:sessionId/rate',
        builder: (context, state) =>
            Scaffold(body: Text('rate ${state.pathParameters['sessionId']}')),
      ),
      GoRoute(
        path: '/sessions/:sessionId',
        builder: (context, state) => Scaffold(
          body: Text('session ${state.pathParameters['sessionId']}'),
        ),
      ),
      GoRoute(
        path: '/tutor-requests',
        builder: (context, state) =>
            const Scaffold(body: Text('tutor requests')),
      ),
      GoRoute(
        path: '/matching',
        builder: (context, state) => const Scaffold(body: Text('matching')),
      ),
      GoRoute(
        path: '/certificate',
        builder: (context, state) => const Scaffold(body: Text('certificate')),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  final router = _router();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// A repository whose first inbox load fails and whose next one answers.
class _FlakyNotificationsRepository extends FakeNotificationsRepository {
  _FlakyNotificationsRepository({super.notifications});

  int calls = 0;

  @override
  Future<NotificationPage> inbox({int limit = 20, int offset = 0}) {
    calls++;
    if (calls == 1) {
      return Future<NotificationPage>.error(const NetworkFailure());
    }
    return super.inbox(limit: limit, offset: offset);
  }
}

/// A repository that cannot mark a row read.
class _ReadFailingRepository extends FakeNotificationsRepository {
  _ReadFailingRepository({super.notifications});

  @override
  Future<AppNotification> markRead(String notificationId) async {
    throw const NetworkFailure();
  }
}

List<AppNotification> _manyUnread(int count) {
  return [
    for (var index = 0; index < count; index++)
      notification(
        id: 'notification-$index',
        title: 'Notification $index',
        type: AppNotificationType.sessionStarted,
        data: {'kind': 'session', 'session_id': 'session-$index'},
      ),
  ];
}

void main() {
  testWidgets('an empty inbox says what would fill it', (tester) async {
    await _pump(tester, _container(FakeNotificationsRepository()));

    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.byTooltip('Mark all read'), findsNothing);
  });

  testWidgets('shows what arrived and marks which rows are unread', (
    tester,
  ) async {
    final container = _container(
      FakeNotificationsRepository(
        notifications: [
          notification(id: 'one'),
          notification(
            id: 'two',
            title: 'You are Verified',
            type: AppNotificationType.promotion,
          ),
          notification(
            id: 'three',
            title: 'Already read',
            readAt: DateTime.utc(2026, 11, 2),
          ),
        ],
      ),
    );

    await _pump(tester, container);

    expect(find.text('New tutoring request'), findsOneWidget);
    expect(find.text('You are Verified'), findsOneWidget);
    expect(find.text('Already read'), findsOneWidget);
    // Two unread rows, each carrying the label a screen reader can hear.
    expect(find.bySemanticsLabel('Unread'), findsNWidgets(2));
    expect(find.byTooltip('Mark all read'), findsOneWidget);
  });

  testWidgets('coming back to the bell asks again', (tester) async {
    final repository = FakeNotificationsRepository();
    final container = _container(repository);
    await _pump(tester, container);

    expect(find.text('Nothing yet'), findsOneWidget);
    expect(repository.inboxOffsets, [0]);

    repository.arrive(
      notification(
        id: 'late',
        title: 'Message from a tutor',
        type: AppNotificationType.messageReceived,
        data: {'kind': 'session', 'session_id': 'session-1'},
      ),
    );

    // Leaving the tab and returning builds a new screen over the same
    // keep-alive provider, which is the case that used to stay on whatever the
    // inbox held when the app signed in.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, container);

    expect(repository.inboxOffsets, [0, 0]);
    expect(find.text('Message from a tutor'), findsOneWidget);
  });

  testWidgets('returning to the app re-reads the bell', (tester) async {
    final repository = FakeNotificationsRepository(
      notifications: [notification(id: 'one')],
    );
    final container = _container(repository);
    await _pump(tester, container);

    repository.arrive(notification(id: 'two', title: 'Second'));

    // A real backgrounding moves through the intermediate states; the binding
    // asserts on the legal transitions.
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await _settle(tester);

    expect(repository.inboxOffsets, [0, 0]);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('one tap clears the badge for the whole inbox', (tester) async {
    final repository = FakeNotificationsRepository(
      notifications: [
        notification(id: 'one'),
        notification(id: 'two'),
      ],
    );
    final container = _container(repository);
    await _pump(tester, container);

    await tester.tap(find.byTooltip('Mark all read'));
    await _settle(tester);

    expect(repository.markAllReadCalls, 1);
    expect(find.bySemanticsLabel('Unread'), findsNothing);
    expect(find.byTooltip('Mark all read'), findsNothing);
    expect(container.read(notificationUnreadCountProvider), 0);
  });

  testWidgets('load older appends the next page', (tester) async {
    final repository = FakeNotificationsRepository(
      notifications: _manyUnread(25),
    );
    final container = _container(repository);
    await _pump(tester, container);

    expect(find.text('Notification 24'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Load older'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Load older'));
    await _settle(tester);

    expect(repository.inboxOffsets, [0, 20]);
    expect(find.text('Load older'), findsNothing);
    expect(container.read(notificationInboxProvider).value!.items.length, 25);

    // The appended page is below the fold, so scroll to it rather than expecting
    // a `ListView` to have built a row that is not on screen.
    await tester.scrollUntilVisible(
      find.text('Notification 24'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Notification 24'), findsOneWidget);
  });

  testWidgets('a failed first load says what happened and retries', (
    tester,
  ) async {
    final repository = _FlakyNotificationsRepository(
      notifications: [notification(id: 'one')],
    );
    await _pump(tester, _container(repository));

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await _settle(tester);

    expect(find.text('New tutoring request'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a new request opens the tutor request list and is read', (
    tester,
  ) async {
    final repository = FakeNotificationsRepository(
      notifications: [
        notification(
          id: 'request-1',
          data: {'kind': 'help_request', 'request_id': 'request-1'},
        ),
      ],
    );
    final container = _container(repository);
    await _pump(tester, container);

    await tester.tap(find.text('New tutoring request'));
    await _settle(tester);

    expect(find.text('tutor requests'), findsOneWidget);
    expect(repository.readIds, ['request-1']);
    expect(container.read(notificationInboxProvider).value!.unreadCount, 0);
  });

  testWidgets('a decline sends the student back to matching', (tester) async {
    await _pump(
      tester,
      _container(
        FakeNotificationsRepository(
          notifications: [
            notification(
              id: 'declined-1',
              type: AppNotificationType.requestDeclined,
              data: {'kind': 'help_request', 'request_id': 'request-1'},
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('New tutoring request'));
    await _settle(tester);

    expect(find.text('matching'), findsOneWidget);
  });

  testWidgets('a completed session opens the rating form it asks for', (
    tester,
  ) async {
    await _pump(
      tester,
      _container(
        FakeNotificationsRepository(
          notifications: [
            notification(
              id: 'completed-1',
              type: AppNotificationType.sessionCompleted,
              data: {'kind': 'session', 'session_id': 'session-9'},
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('New tutoring request'));
    await _settle(tester);

    expect(find.text('rate session-9'), findsOneWidget);
  });

  testWidgets('a promotion opens the certificate screen', (tester) async {
    await _pump(
      tester,
      _container(
        FakeNotificationsRepository(
          notifications: [
            notification(
              id: 'promotion-1',
              type: AppNotificationType.promotion,
              title: 'You are Verified',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('You are Verified'));
    await _settle(tester);

    expect(find.text('certificate'), findsOneWidget);
  });

  testWidgets('a row with nowhere to go is still marked read', (tester) async {
    // An unknown type has a title and a body but no destination. Tapping it must
    // not strand the student on a broken route or leave the badge loud.
    final repository = FakeNotificationsRepository(
      notifications: [
        notification(
          id: 'newer-event',
          type: AppNotificationType.unknown,
          title: 'Something new happened',
        ),
      ],
    );
    final container = _container(repository);
    await _pump(tester, container);

    await tester.tap(find.text('Something new happened'));
    await _settle(tester);

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(repository.readIds, ['newer-event']);
    expect(container.read(notificationInboxProvider).value!.unreadCount, 0);
  });

  testWidgets('a failed read keeps the list and explains above it', (
    tester,
  ) async {
    await _pump(
      tester,
      _container(
        _ReadFailingRepository(
          notifications: [
            notification(
              id: 'started-1',
              type: AppNotificationType.sessionStarted,
              title: 'Session started',
              // No session id, so the tap stays on the inbox where the banner
              // can be seen. A destination would hide the failure behind a push.
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Session started'));
    await _settle(tester);

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('Session started'), findsOneWidget);
    expect(find.bySemanticsLabel('Unread'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/messages/data/models/session_message.dart';
import 'package:peerpass/features/messages/data/repositories/fake_messages_repository.dart';
import 'package:peerpass/features/messages/data/repositories/messages_repository.dart';
import 'package:peerpass/features/messages/presentation/providers/session_thread_provider.dart';
import 'package:peerpass/features/messages/presentation/screens/session_chat_screen.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/fake_sessions_repository.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';
import 'package:peerpass/features/sessions/presentation/screens/session_detail_screen.dart';

const UserProfile _tutee = UserProfile(
  publicId: 'student-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 2,
);

const UserProfile _tutor = UserProfile(
  publicId: 'tutor-1',
  email: 'tutor@must.ac.ug',
  fullName: 'Daniel Okot',
  roles: <UserRole>{UserRole.student, UserRole.tutor},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 3,
);

const String _sessionId = 'session-1';

SessionModel _session({String status = 'scheduled'}) {
  return SessionModel.fromJson({
    'id': _sessionId,
    'tutee_id': _tutee.publicId,
    'tutor_id': _tutor.publicId,
    'course_unit_id': 'unit-1',
    'course_unit_code': 'MAT 221',
    'course_unit_name': 'Linear Algebra',
    'tutee_name': 'Adongo Sarah',
    'tutor_name': 'Okello Daniel',
    'topic': 'Second order ODEs',
    'status': status,
    'duration_minutes': 60,
    'created_at': '2026-03-01T08:00:00Z',
    'scheduled_start': '2026-03-04T09:00:00Z',
  });
}

SessionMessage _message({
  String id = 'message-1',
  String senderId = 'tutor-1',
  String body = 'Library at 4?',
  DateTime? readAt,
}) {
  return SessionMessage(
    id: id,
    sessionId: _sessionId,
    senderId: senderId,
    body: body,
    createdAt: DateTime.utc(2026, 3, 2, 9),
    readAt: readAt,
  );
}

ProviderContainer _container({
  required FakeMessagesRepository messages,
  List<SessionModel>? sessions,
  Duration pollInterval = const Duration(seconds: 30),
}) {
  final container = ProviderContainer(
    overrides: [
      messagesRepositoryProvider.overrideWithValue(messages),
      sessionsRepositoryProvider.overrideWithValue(
        FakeSessionsRepository(sessions: sessions ?? [_session()]),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(session: _tutee, refreshToken: 'refresh'),
      ),
      messagePollIntervalProvider.overrideWithValue(pollInterval),
    ],
  );
  addTearDown(container.dispose);
  messages.currentUserId = _tutee.publicId;
  container.read(sessionControllerProvider.notifier).signedIn(_tutee);
  return container;
}

Future<void> _pumpChat(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SessionChatScreen(sessionId: _sessionId),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Takes the screen down so its poll timer is cancelled before the test ends.
///
/// The scope stays mounted with an empty child rather than being replaced
/// wholesale: Riverpod drops a scheduled auto-dispose when the scope itself is
/// unmounted, which a real app never does -- the shell outlives every screen, and
/// leaving the chat is only a screen going away. Unmounting the scope as well
/// would leave the thread provider alive with its timer running, and the test
/// would be exercising a shutdown path instead of the one that ships.
Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SizedBox.shrink(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('names the other party and what the thread is about', (
    tester,
  ) async {
    final container = _container(
      messages: FakeMessagesRepository(messages: [_message()]),
    );

    await _pumpChat(tester, container);

    // The tutor's name, not the public id: this is the person the student is
    // agreeing to meet.
    expect(find.text('Okello Daniel'), findsOneWidget);
    expect(find.text('MAT 221 · Linear Algebra'), findsOneWidget);
    // The message itself, on the side of whoever wrote it. There is no name
    // above a bubble on purpose; the side is the whole grammar of a chat.
    expect(find.text('Library at 4?'), findsOneWidget);

    await _close(tester, container);
  });

  testWidgets('says so plainly when nobody has written yet', (tester) async {
    final container = _container(messages: FakeMessagesRepository());

    await _pumpChat(tester, container);

    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await _close(tester, container);
  });

  testWidgets('sending appends the message and clears the box', (tester) async {
    final messages = FakeMessagesRepository();
    final container = _container(messages: messages);

    await _pumpChat(tester, container);

    await tester.enterText(find.byType(TextField), 'Library at 4?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester);

    expect(messages.sentBodies, ['Library at 4?']);
    expect(find.text('Library at 4?'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);

    await _close(tester, container);
  });

  testWidgets('a refused send keeps the draft to try again', (tester) async {
    final messages = FakeMessagesRepository();
    final container = _container(messages: messages);
    await _pumpChat(tester, container);

    messages.sendFailure = const NetworkFailure();
    await tester.enterText(find.byType(TextField), 'Library at 4?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester);

    // The failure, plus the fact that the text survived it. A chat that dropped
    // the draft on a refused send makes a student retype a message they had
    // already written, on exactly the connection that just failed.
    expect(find.textContaining('Your message is still here.'), findsOneWidget);
    expect(find.textContaining(const NetworkFailure().message), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Library at 4?');

    await _close(tester, container);
  });

  testWidgets('a message the other party wrote arrives on its own', (
    tester,
  ) async {
    final messages = FakeMessagesRepository();
    final container = _container(
      messages: messages,
      pollInterval: const Duration(seconds: 1),
    );

    await _pumpChat(tester, container);
    expect(find.text('No messages yet'), findsOneWidget);

    // Delivered the way the real one is: the server has it, the client has not
    // asked yet.
    messages.deliver(
      sessionId: _sessionId,
      senderId: _tutor.publicId,
      body: 'Room 12 works better',
    );

    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    expect(find.text('Room 12 works better'), findsOneWidget);
    // And it is marked read, because it is on screen. The badge on the sessions
    // list has no business staying lit for a thread the student just read.
    expect(messages.markedReadSessionIds, [_sessionId]);

    await _close(tester, container);
  });

  testWidgets('opening a thread with unread messages marks them read', (
    tester,
  ) async {
    final messages = FakeMessagesRepository(messages: [_message()]);
    final container = _container(messages: messages);

    await _pumpChat(tester, container);

    expect(messages.markedReadSessionIds, [_sessionId]);
    expect(messages.storedMessages.single.isRead, isTrue);

    await _close(tester, container);
  });

  testWidgets('a thread that cannot be read offers another try', (tester) async {
    final messages = FakeMessagesRepository()..listFailure = const NetworkFailure();
    final container = _container(messages: messages);

    await _pumpChat(tester, container);

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    messages.listFailure = null;
    await tester.tap(find.text('Try again'));
    await _settle(tester);

    expect(find.text('No messages yet'), findsOneWidget);

    await _close(tester, container);
  });

  testWidgets('a session that did not happen keeps its history and closes', (
    tester,
  ) async {
    final container = _container(
      messages: FakeMessagesRepository(messages: [_message()]),
      sessions: [_session(status: 'cancelled')],
    );

    await _pumpChat(tester, container);

    // What was agreed is exactly what matters after a cancellation, so the list
    // stays. The API refuses a message on a cancelled session, so the box goes.
    expect(find.text('Library at 4?'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('This session did not take place, so the thread is closed.'),
      findsOneWidget,
    );

    await _close(tester, container);
  });

  testWidgets('polling stops while the app is in the background', (tester) async {
    final messages = FakeMessagesRepository();
    final container = _container(
      messages: messages,
      pollInterval: const Duration(seconds: 1),
    );

    await _pumpChat(tester, container);
    final readsWhileOpen = messages.readCursors.length;

    // A real backgrounding moves through the intermediate states; the binding
    // asserts on the legal transitions and an expensive jump is not the case
    // under test.
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump(const Duration(seconds: 5));
    expect(
      messages.readCursors.length,
      readsWhileOpen,
      reason: 'a backgrounded chat must not spend data on empty polls',
    );

    [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      messages.readCursors.length,
      greaterThan(readsWhileOpen),
      reason: 'coming back to the app is the moment it should be current',
    );

    await _close(tester, container);
  });

  testWidgets('the session screen opens the thread', (tester) async {
    final messages = FakeMessagesRepository(messages: [_message()]);
    final container = _container(messages: messages);

    final router = GoRouter(
      initialLocation: '/sessions/$_sessionId',
      routes: [
        GoRoute(
          path: '/sessions/:sessionId',
          builder: (context, state) =>
              SessionDetailScreen(sessionId: state.pathParameters['sessionId']!),
        ),
        GoRoute(
          path: '/sessions/:sessionId/messages',
          builder: (context, state) =>
              SessionChatScreen(sessionId: state.pathParameters['sessionId']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await _settle(tester);

    final messageButton = find.text('Message');
    await tester.ensureVisible(messageButton);
    await tester.pump();
    await tester.tap(messageButton);
    await _settle(tester);

    expect(find.text('Library at 4?'), findsOneWidget);

    await _close(tester, container);
  });
}

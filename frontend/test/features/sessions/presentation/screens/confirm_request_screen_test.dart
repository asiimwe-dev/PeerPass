import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/fake_sessions_repository.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';
import 'package:peerpass/features/sessions/presentation/screens/confirm_request_screen.dart';

const UserProfile _tutor = UserProfile(
  publicId: 'tutor-1',
  email: 'tutor@must.ac.ug',
  fullName: 'Daniel Okot',
  roles: <UserRole>{UserRole.student, UserRole.tutor},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 3,
);

const String _requestId = 'request-1';
const String _courseUnitId = 'unit-1';
const String _topic = 'How does a characteristic polynomial work?';

ProviderContainer _container(SessionsRepository repository) {
  final container = ProviderContainer(
    overrides: [
      sessionsRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(session: _tutor, refreshToken: 'refresh'),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier).signedIn(_tutor);
  return container;
}

/// The router the app builds, so the route under test is the app's route.
///
/// The path comes from [AppRoutes.confirmRequestPath] rather than a literal, so a
/// rename of the route or of one of its three values fails here instead of only in
/// the running app. The confirm screen navigates with `go` on success, so the
/// router needs a destination for that.
Future<
  ({
    FakeSessionsRepository fake,
    SessionsRepository repository,
    List<String> visited,
    GoRouter router,
  })
>
_pumpConfirm(
  WidgetTester tester, {
  SessionsRepository? repository,
  List<String>? visited,
}) async {
  // Mutable by construction rather than defaulted to a const list, because the
  // routes record where they were visited and a const list refuses that.
  final visitedLocations = visited ?? <String>[];
  final fake = FakeSessionsRepository()
    ..withPendingStudent('student-1', tutorId: 'tutor-1');
  final sessions = repository ?? fake;

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) {
          visitedLocations.add(AppRoutes.home);
          return const Scaffold();
        },
      ),
      GoRoute(
        path: '${AppRoutes.sessions}/confirm',
        builder: (context, state) {
          visitedLocations.add(state.uri.toString());
          final query = state.uri.queryParameters;
          return ConfirmRequestScreen(
            requestId: query['request'] ?? '',
            courseUnitId: query['unit'] ?? '',
            topic: query['topic'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.sessions}/:sessionId',
        builder: (context, state) {
          visitedLocations.add(state.uri.toString());
          return Scaffold(
            body: Text('session ${state.pathParameters['sessionId']}'),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(sessions),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  unawaited(
    router.push(
      AppRoutes.confirmRequestPath(
        requestId: _requestId,
        courseUnitId: _courseUnitId,
        topic: _topic,
      ),
    ),
  );
  await _settle(tester);
  return (
    fake: fake,
    repository: sessions,
    visited: visitedLocations,
    router: router,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Finder _confirmButton() => find.widgetWithText(FilledButton, 'Confirm');
bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_confirmButton()).onPressed != null;

void main() {
  group('the request being confirmed', () {
    testWidgets("the student's question is what the tutor reads", (tester) async {
      await _pumpConfirm(tester);

      expect(find.text(_topic), findsOneWidget);
    });

    testWidgets('the unit and topic are not asked for again', (tester) async {
      await _pumpConfirm(tester);

      // One field, and it is the length. Asking the tutor to retype what the
      // student wrote would invite the mismatch the API then refuses, in front of
      // a tutor who did nothing wrong.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('How long, in minutes?'), findsOneWidget);
    });
  });

  group('the length', () {
    testWidgets('confirming is impossible until one is typed', (tester) async {
      await _pumpConfirm(tester);

      expect(_enabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();

      expect(_enabled(tester), isTrue);
    });

    testWidgets('a length of zero does not enable the button', (tester) async {
      await _pumpConfirm(tester);

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      // The API refuses a zero-minute session, so offering the button would be a
      // promise the server keeps breaking.
      expect(_enabled(tester), isFalse);
    });

    testWidgets("the API's own bounds are not restated on the screen", (
      tester,
    ) async {
      await _pumpConfirm(tester);

      // 481 is past what the API accepts. The client does not know the ceiling --
      // it is the API's rule and a client copy would be one that drifts -- so the
      // button is offered and the refusal comes back from the server.
      await tester.enterText(find.byType(TextField), '481');
      await tester.pump();

      expect(_enabled(tester), isTrue);
    });

    testWidgets('a length that is not a number does not enable the button', (
      tester,
    ) async {
      await _pumpConfirm(tester);

      // The keyboard is numeric so this is hard to type, but a pasted value or an
      // accessibility keyboard can produce it. Guessing at what the tutor meant
      // is not the screen's decision.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(_enabled(tester), isFalse);
    });

    testWidgets('the typed length survives leaving and coming back', (
      tester,
    ) async {
      final harness = await _pumpConfirm(tester);

      await tester.enterText(find.byType(TextField), '75');
      await tester.pump();

      // The back gesture is one swipe away on Android and this is a route, so a
      // tutor who loses a typed length to it has to reopen the request and start
      // again. The draft lives in the provider for exactly that reason.
      await tester.pageBack();
      await _settle(tester);
      expect(find.text(_topic), findsNothing);

      unawaited(
        harness.router.push(
          AppRoutes.confirmRequestPath(
            requestId: _requestId,
            courseUnitId: _courseUnitId,
            topic: _topic,
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('75'), findsOneWidget);
    });
  });

  group('confirming', () {
    testWidgets('sends the request, the unit, the topic and the length', (
      tester,
    ) async {
      final harness = await _pumpConfirm(tester);

      await tester.enterText(find.byType(TextField), '45');
      await tester.pump();
      await tester.tap(_confirmButton());
      await _settle(tester);

      final fake = harness.repository as FakeSessionsRepository;
      expect(fake.confirmations, hasLength(1));
      expect(fake.confirmations.single.requestId, _requestId);
      expect(fake.confirmations.single.courseUnitId, _courseUnitId);
      expect(fake.confirmations.single.topic, _topic);
      expect(fake.confirmations.single.durationMinutes, 45);
    });

    testWidgets('opens the session it created, where the PIN is', (
      tester,
    ) async {
      final harness = await _pumpConfirm(tester);

      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();
      await tester.tap(_confirmButton());
      await _settle(tester);

      // The tutor agreed to a specific session and the PIN that starts it is on
      // it. Landing on the list would make them hunt for what they just booked.
      expect(harness.visited.last, '/sessions/session-from-$_requestId');
      expect(find.text('session session-from-$_requestId'), findsOneWidget);
    });

    testWidgets('does not fire twice while the request is in flight', (
      tester,
    ) async {
      final gate = Completer<void>();
      // A repository that holds the answer open, so the second tap lands while the
      // first is still waiting. Two confirmations would be two sessions for one
      // question, and the API's unique constraint would refuse the loser anyway.
      final fake = FakeSessionsRepository()
        ..withPendingStudent('student-1', tutorId: 'tutor-1');
      final slow = _SlowConfirmRepository(fake, gate);
      await _pumpConfirm(tester, repository: slow);

      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();

      await tester.tap(_confirmButton());
      await tester.pump();

      // While the request is out, the button shows progress instead of its label
      // and cannot be pressed again. That is what stops the second tap; the API's
      // unique constraint refusing the duplicate afterwards would be a worse
      // answer, because the tutor would see a failure for something already done.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull,
      );
      expect(slow.calls, 1);

      // A tap aimed at where the button was is not a second request either.
      await tester.tap(find.byType(FilledButton).first, warnIfMissed: false);
      await tester.pump();
      expect(slow.calls, 1);

      gate.complete();
      await _settle(tester);

      // Still one, after the first answer lands and the screen moves on.
      expect(slow.calls, 1);
      expect(fake.confirmations, hasLength(1));
    });
  });

  group('when the API refuses', () {
    testWidgets('the reason is on the form and the length is kept', (
      tester,
    ) async {
      const refusing = _RefusingConfirmRepository(
        ValidationFailure(
          'That length is not one the API accepts.',
          fieldErrors: {'duration_minutes': 'must be at most 480'},
        ),
      );
      await _pumpConfirm(tester, repository: refusing);

      await tester.enterText(find.byType(TextField), '481');
      await tester.pump();
      await tester.tap(_confirmButton());
      await _settle(tester);

      expect(
        find.text('That length is not one the API accepts.'),
        findsOneWidget,
      );
      // Still on the form, still holding what was typed. The tutor has to be able
      // to correct one number without retyping it and without losing their place.
      expect(_confirmButton(), findsOneWidget);
      expect(find.text('481'), findsOneWidget);
    });

    testWidgets('a dropped connection says so without transport text', (
      tester,
    ) async {
      await _pumpConfirm(
        tester,
        // The default message, so this asserts the copy a person reads rather
        // than a string this test supplied.
        repository: const _RefusingConfirmRepository(NetworkFailure()),
      );

      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();
      await tester.tap(_confirmButton());
      await _settle(tester);

      expect(
        find.text('No connection. Check your network and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('a second confirmation is reported as a conflict', (
      tester,
    ) async {
      await _pumpConfirm(
        tester,
        repository: const _RefusingConfirmRepository(
          ConflictFailure('This help request is not waiting for your answer.'),
        ),
      );

      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();
      await tester.tap(_confirmButton());
      await _settle(tester);

      expect(
        find.text('This help request is not waiting for your answer.'),
        findsOneWidget,
      );
    });

    testWidgets('the screen offers a way out while it is waiting', (
      tester,
    ) async {
      await _pumpConfirm(tester);

      expect(find.widgetWithText(TextButton, 'Not now'), findsOneWidget);
    });
  });
}

/// Holds the repository's answer open, to prove a double tap sends one request.
class _SlowConfirmRepository implements SessionsRepository {
  _SlowConfirmRepository(this._inner, this._gate);

  final FakeSessionsRepository _inner;
  final Completer<void> _gate;

  int calls = 0;

  @override
  Future<SessionModel> confirmRequest({
    required String requestId,
    required String courseUnitId,
    required String topic,
    required int durationMinutes,
  }) async {
    calls += 1;
    await _gate.future;
    return await _inner.confirmRequest(
      requestId: requestId,
      courseUnitId: courseUnitId,
      topic: topic,
      durationMinutes: durationMinutes,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not under test');
}

/// Answers every confirmation with one failure.
///
/// A repository that always refuses rather than one that refuses once, so a test
/// that taps twice cannot accidentally prove the wrong thing about idempotency.
class _RefusingConfirmRepository implements SessionsRepository {
  const _RefusingConfirmRepository(this.failure);

  final Failure failure;

  @override
  Future<SessionModel> confirmRequest({
    required String requestId,
    required String courseUnitId,
    required String topic,
    required int durationMinutes,
  }) async {
    throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not under test');
}

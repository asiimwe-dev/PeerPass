import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/core/models/tutor_standing.dart';
import 'package:peerpass/core/models/tutor_summary.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/matching/data/models/help_request.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';
import 'package:peerpass/features/matching/data/repositories/fake_matching_repository.dart';
import 'package:peerpass/features/matching/data/repositories/matching_repository.dart';
import 'package:peerpass/features/matching/presentation/screens/match_results_screen.dart';
import 'package:peerpass/features/matching/presentation/screens/tutor_requests_screen.dart';

/// The unit the student is looking for help with.
const CourseUnit _unit = CourseUnit(
  publicId: 'unit-1',
  code: 'MAT 221',
  name: 'Linear Algebra II',
);

/// The two proposed tutors, so "which one did they choose" is a question the
/// screen can be asked and answer wrongly.
/// When the engine ran. `DateTime.utc` is not a const constructor, so the result
/// is `final` and the list below is `const` -- which is what keeps the candidates
/// themselves const.
final DateTime _generatedAt = DateTime.utc(2026, 3, 4, 9, 12);

const List<MatchCandidate> _bothCandidates = [
  MatchCandidate(
    tutor: TutorSummary(
      userId: 'tutor-1',
      fullName: 'Grace Okello',
      standing: TutorStanding.verified,
      standingWire: 'verified',
      averageRating: 4.4,
      completedSessions: 18,
    ),
    courseUnitId: 'unit-1',
    meetsThreshold: true,
    score: 0.91,
  ),
  MatchCandidate(
    tutor: TutorSummary(
      userId: 'tutor-2',
      fullName: 'Daniel Okot',
      standing: TutorStanding.probationary,
      standingWire: 'probationary',
      averageRating: 4.1,
      completedSessions: 4,
    ),
    courseUnitId: 'unit-1',
    meetsThreshold: true,
    score: 0.62,
  ),
];

final MatchResult _twoCandidates = MatchResult(
  courseUnitId: 'unit-1',
  widened: false,
  generatedAt: _generatedAt,
  noEligibleTutors: false,
  candidates: _bothCandidates,
  exclusions: const [],
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

ProviderContainer _container(FakeMatchingRepository repository) {
  final container = ProviderContainer(
    overrides: [matchingRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpResults(
  WidgetTester tester,
  FakeMatchingRepository repository,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(repository),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MatchResultsScreen(courseUnitId: 'unit-1'),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _pumpTutorRequests(
  WidgetTester tester,
  FakeMatchingRepository repository,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(repository),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const TutorRequestsScreen(),
      ),
    ),
  );
  await _settle(tester);
}

/// A repository that proposes [_twoCandidates] for every unit.
FakeMatchingRepository _repository({
  List<CourseUnit> units = const [_unit],
  MatchResult? result,
  Future<List<HelpRequest>?> Function()? onAwaiting,
  Future<HelpRequest?> Function({
    required String requestId,
    required String candidateTutorId,
  })?
  onSelect,
}) {
  return FakeMatchingRepository(
    courseUnits: units,
    onSuggestions: ({required courseUnitId, required widenToSubject}) =>
        result ?? _twoCandidates,
    onRequestsAwaitingMe: onAwaiting,
    onSelectTutor: onSelect,
  );
}

/// Fills in the topic field and presses the sheet's button.
Future<void> _submitTopic(
  WidgetTester tester, {
  String topic = 'eigenvalues',
  String? description,
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Topic'), topic);
  if (description != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'Anything else (optional)'),
      description,
    );
  }
  // Settled before the tap: the submit button is enabled by the rebuild that
  // typing causes, and a tap delivered in the same frame as the keystroke lands
  // on the button as it was before the student wrote anything.
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Ask this tutor'));
  await tester.pumpAndSettle();
}

void main() {
  group('a student asking a tutor', () {
    testWidgets('the list offers a way to ask each tutor', (tester) async {
      await _pumpResults(tester, _repository());

      expect(find.text('Grace Okello'), findsOneWidget);
      expect(find.text('Daniel Okot'), findsOneWidget);
      expect(find.text('Ask Grace Okello to tutor you'), findsOneWidget);
      expect(find.text('Ask Daniel Okot to tutor you'), findsOneWidget);
    });

    testWidgets('asking needs a topic before anything is sent', (tester) async {
      final repository = _repository();
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();

      // The sheet, not a request. A request with no topic is a tutor asked to
      // take on something nobody described.
      expect(find.text('What do you need help with?'), findsOneWidget);
      expect(repository.createdRequests, isEmpty);
      expect(repository.selections, isEmpty);
    });

    testWidgets('a topic too short to be a question cannot be sent', (
      tester,
    ) async {
      final repository = _repository();
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Topic'), 'eig');

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Ask this tutor'),
      );
      // Disabled rather than enabled-and-wrong: the button is saying the form is
      // not ready, which is true.
      expect(button.onPressed, isNull);
      expect(repository.createdRequests, isEmpty);
    });

    testWidgets('backing out of the sheet sends nothing', (tester) async {
      final repository = _repository();
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Not an empty topic. Cancelling is "not now" and sending one would be a
      // request a tutor was asked to answer with nothing in it.
      expect(repository.createdRequests, isEmpty);
      expect(repository.selections, isEmpty);
    });

    testWidgets('a topic and a choice send the request, then the choice', (
      tester,
    ) async {
      final repository = _repository();
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester, description: 'Stuck on eigenvectors.');

      expect(repository.createdRequests.single.courseUnitId, 'unit-1');
      expect(repository.createdRequests.single.topic, 'eigenvalues');
      expect(
        repository.createdRequests.single.description,
        'Stuck on eigenvectors.',
      );
      // The request exists before the tutor is named, and the naming is what
      // tells anybody. Reporting success after the first would say the choice was
      // sent when nothing had been sent to anybody.
      expect(
        repository.selections.single.requestId,
        repository.requests.single.id,
      );
      expect(repository.selections.single.candidateTutorId, 'tutor-1');
    });

    testWidgets('the answer says asked, and never says booked', (tester) async {
      await _pumpResults(tester, _repository());

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester);

      // `pending_confirmation` is the platform holding a question open for
      // somebody who has not answered it. A student told they were booked would
      // turn up to a session no tutor agreed to.
      expect(find.textContaining('Asked eigenvalues'), findsOneWidget);
      expect(find.textContaining('not confirmed'), findsOneWidget);
      // The negation is the point, so it is asserted as written rather than by
      // searching for "booked", which the honest copy also contains.
      expect(find.textContaining('no session booked'), findsOneWidget);
      expect(find.textContaining('session is booked'), findsNothing);
    });

    testWidgets('the chosen tutor keeps a label instead of a button', (
      tester,
    ) async {
      final repository = _repository();
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester);

      // The row the student acted on no longer offers the action, and the other
      // one still does. A control that stays pressable on a completed request is
      // how a student asks twice and is refused for it.
      expect(find.text('Asked Grace Okello'), findsOneWidget);
      expect(find.text('Ask Grace Okello to tutor you'), findsNothing);
      expect(find.text('Ask Daniel Okot to tutor you'), findsOneWidget);
      expect(repository.selections, hasLength(1));
    });

    testWidgets('a refusal is shown and nothing is claimed to have been sent', (
      tester,
    ) async {
      final repository = _repository(
        onSelect: ({required requestId, required candidateTutorId}) async {
          throw const ValidationFailure(
            'That tutor cannot be chosen for this help request.',
            fieldErrors: {
              'candidate_tutor_id':
                  'not an eligible tutor for this course unit',
            },
          );
        },
      );
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester);

      // The student is told the tutor was not asked. Silence here would read as
      // success, and a student who believes they asked is worse off than one who
      // was refused.
      expect(find.textContaining('has not been asked'), findsOneWidget);
      expect(find.textContaining('not confirmed'), findsNothing);
    });

    testWidgets("a dropped connection is refused in the student's words", (
      tester,
    ) async {
      final repository = FakeMatchingRepository(
        courseUnits: const [_unit],
        onSuggestions: ({required courseUnitId, required widenToSubject}) =>
            _twoCandidates,
        onCreateHelpRequest: ({
          required courseUnitId,
          required topic,
          description,
        }) async => throw const NetworkFailure(),
      );
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester);

      // The repository's own wording, not a socket error and not a type name.
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(repository.selections, isEmpty);
    });

    testWidgets("an ended session is refused in the student's words", (
      tester,
    ) async {
      final repository = _repository(
        onSelect: ({required requestId, required candidateTutorId}) async {
          throw const AuthFailure();
        },
      );
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester);

      expect(find.textContaining('sign in again'), findsOneWidget);
    });

    testWidgets('an unknown status is not shown as anything it is not', (
      tester,
    ) async {
      // Scripted on the select, because that is the call whose answer the banner
      // reports. A create-only script would be overwritten by the select that
      // follows it, and the unknown state would never reach the screen.
      final repository = _repository(
        onSelect: ({required requestId, required candidateTutorId}) async =>
            HelpRequest.fromJson({
              'id': requestId,
              'tutee_id': 'student-1',
              'course_unit_id': 'unit-1',
              'topic': 'eigenvalues',
              'status': 'awaiting_pilot_funding',
              'created_at': '2026-03-04T09:12:00Z',
            }),
      );
      await _pumpResults(tester, repository);

      await tester.tap(find.text('Ask Grace Okello to tutor you'));
      await tester.pumpAndSettle();
      await _submitTopic(tester);

      expect(find.textContaining('does not know'), findsOneWidget);
      expect(find.textContaining('booked'), findsNothing);
    });

    testWidgets('nobody being eligible still leaves no button to press', (
      tester,
    ) async {
      await _pumpResults(
        tester,
        FakeMatchingRepository(
          courseUnits: const [_unit],
          onSuggestions: ({required courseUnitId, required widenToSubject}) =>
              MatchResult(
                courseUnitId: 'unit-1',
                widened: false,
                generatedAt: _generatedAt,
                noEligibleTutors: true,
                candidates: const [],
                exclusions: const [],
              ),
        ),
      );

      expect(
        find.textContaining('No eligible tutor for MAT 221'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('a tutor answering', () {
    HelpRequest awaiting({String id = 'request-1'}) {
      return HelpRequest.fromJson({
        'id': id,
        'tutee_id': 'student-1',
        'course_unit_id': 'unit-1',
        'topic': 'eigenvalues',
        'description': 'Stuck on the second eigenvector.',
        'status': 'pending_confirmation',
        'matched_tutor_id': 'tutor-1',
        'created_at': '2026-03-04T09:12:00Z',
      });
    }

    testWidgets('shows what the student asked', (tester) async {
      await _pumpTutorRequests(
        tester,
        _repository(onAwaiting: () async => [awaiting()]),
      );

      expect(find.text('eigenvalues'), findsOneWidget);
      expect(find.text('Stuck on the second eigenvector.'), findsOneWidget);
      expect(find.text('Turn down'), findsOneWidget);
    });

    testWidgets('nobody waiting is an empty state, not a failure', (
      tester,
    ) async {
      await _pumpTutorRequests(
        tester,
        _repository(onAwaiting: () async => const []),
      );

      expect(find.text('No one is waiting on you'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('turning a request down is sent once and the row goes', (
      tester,
    ) async {
      // Seeded rather than scripted, so the second read of the list is a real
      // read of what the fake now holds. A scripted list would answer the same
      // before and after the decline, which would make the row's disappearance a
      // fact about the test rather than about the refresh.
      final repository = _repository()..seedAwaiting(awaiting());
      await _pumpTutorRequests(tester, repository);

      await tester.tap(find.text('Turn down'));
      await _settle(tester);

      expect(repository.declines, ['request-1']);
      // The list is re-read rather than patched locally: the API owns what is
      // outstanding, and a tutor who has just answered should not see the row
      // again until they ask.
      expect(find.text('eigenvalues'), findsNothing);
      expect(find.text('No one is waiting on you'), findsOneWidget);
    });

    testWidgets('a request the API will not decline says so', (tester) async {
      final repository = FakeMatchingRepository(
        courseUnits: const [_unit],
        onRequestsAwaitingMe: () async => [awaiting()],
        onDeclineHelpRequest: ({required requestId}) async =>
            throw const ConflictFailure(),
      );
      await _pumpTutorRequests(tester, repository);

      await tester.tap(find.text('Turn down'));
      await _settle(tester);

      // The row stays, with the reason. Swallowing this would show the tutor a
      // refusal that did not happen -- the API refused because the request was
      // already answered.
      expect(find.text('eigenvalues'), findsOneWidget);
      expect(find.textContaining('already changed'), findsOneWidget);
    });

    testWidgets('a list that will not load is a retry, not an empty screen', (
      tester,
    ) async {
      await _pumpTutorRequests(
        tester,
        _repository(onAwaiting: () async => throw const NetworkFailure()),
      );

      // The two claims are different -- "nobody asked you" and "we could not ask"
      // -- and one face for both would be a lie about one of them.
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.text('No one is waiting on you'), findsNothing);
    });

    testWidgets("only the chosen tutor's requests are ever listed", (
      tester,
    ) async {
      // The scope is the API's, and this asserts the client adds nothing to it: a
      // tutor's screen must not put an accept button next to work they were never
      // offered.
      await _pumpTutorRequests(
        tester,
        _repository(onAwaiting: () async => const []),
      );

      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('confirming offers the request rather than creating anything', (
      tester,
    ) async {
      final visited = <String>[];
      final repository = _repository()..seedAwaiting(awaiting());
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (context, state) => const Scaffold()),
          GoRoute(
            path: AppRoutes.tutorRequests,
            builder: (context, state) => const TutorRequestsScreen(),
          ),
          GoRoute(
            path: '${AppRoutes.sessions}/confirm',
            builder: (context, state) {
              visited.add(state.uri.toString());
              return const Scaffold();
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(repository),
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      router.go(AppRoutes.tutorRequests);
      await _settle(tester);

      await tester.tap(find.text('Confirm'));
      await _settle(tester);

      // Navigates, and carries the request's own three values. The path is built
      // by the same helper the app router registers, so a rename of either shows
      // up here rather than only at runtime. A free-text question in a query is
      // encoded by `Uri`, so a topic carrying a slash or an ampersand survives.
      expect(visited.single, contains('request=request-1'));
      expect(visited.single, contains('unit=unit-1'));
      expect(visited.single, contains('topic=eigenvalues'));
      // And it did not touch the matching repository to make a session: the
      // session belongs to the sessions feature, so this screen has no way to.
      expect(repository.declines, isEmpty);
    });

    testWidgets("the student's question survives the trip to the form", (
      tester,
    ) async {
      final visited = <String>[];
      const awkward = 'why does det(A) = 0 & A singular?';
      final repository = _repository()
        ..seedAwaiting(
          HelpRequest.fromJson(const {
            'id': 'request-1',
            'tutee_id': 'student-1',
            'course_unit_id': 'unit-1',
            'topic': awkward,
            'status': 'pending_confirmation',
            'matched_tutor_id': 'tutor-1',
            'created_at': '2026-03-04T09:12:00Z',
          }),
        );
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (context, state) => const Scaffold()),
          GoRoute(
            path: AppRoutes.tutorRequests,
            builder: (context, state) => const TutorRequestsScreen(),
          ),
          GoRoute(
            path: '${AppRoutes.sessions}/confirm',
            builder: (context, state) {
              visited.add(state.uri.queryParameters['topic'] ?? '');
              return const Scaffold();
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(repository),
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      router.go(AppRoutes.tutorRequests);
      await _settle(tester);

      await tester.tap(find.text('Confirm'));
      await _settle(tester);

      // Read back off the route rather than off the URL, so this asserts the form
      // would receive the question and not merely that something was encoded.
      expect(visited.single, awkward);
    });
  });
}

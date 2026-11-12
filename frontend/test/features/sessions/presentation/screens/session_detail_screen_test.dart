import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/sessions/data/models/rating_model.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/fake_sessions_repository.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';
import 'package:peerpass/features/sessions/presentation/screens/session_detail_screen.dart';

/// The student in the sessions below.
const UserProfile _tutee = UserProfile(
  publicId: 'student-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 2,
);

/// The other party, so both sides of the handshake can be driven.
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

SessionModel session({
  String status = 'scheduled',
  bool isRated = false,
  String? meetingLink,
  String? meetingVenue,
  String? meetingVenueDetail,
  String? startedAt,
  String? tutorCheckedInAt,
  String? tuteeCheckedInAt,
  String? tutorFinishedAt,
  String? tuteeFinishedAt,
}) {
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
    'is_rated': isRated,
    'created_at': '2026-03-01T08:00:00Z',
    'scheduled_start': '2026-03-04T09:00:00Z',
    'started_at': startedAt,
    'tutor_checked_in_at': tutorCheckedInAt,
    'tutee_checked_in_at': tuteeCheckedInAt,
    'tutor_finished_at': tutorFinishedAt,
    'tutee_finished_at': tuteeFinishedAt,
    'meeting_link': meetingLink,
    'meeting_venue': meetingVenue,
    'meeting_venue_detail': meetingVenueDetail,
  });
}

/// A container holding [session], signed in as [profile].
ProviderContainer _container(
  FakeSessionsRepository repository,
  UserProfile profile,
) {
  final container = ProviderContainer(
    overrides: [
      sessionsRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(session: profile, refreshToken: 'refresh'),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier).signedIn(profile);
  return container;
}

Future<void> _pumpDetail(
  WidgetTester tester,
  FakeSessionsRepository repository,
  UserProfile profile,
) async {
  // The API reads the acting party from the access token; the fake takes it
  // from here so a tutor's tap records the tutor's timestamp.
  repository.currentUser = profile.publicId;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(repository, profile),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SessionDetailScreen(sessionId: _sessionId),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// A repository whose one session cannot be loaded.
class _MissingSessionRepository extends FakeSessionsRepository {
  @override
  Future<SessionModel> session(String sessionId) async {
    throw const NotFoundFailure('That session could not be found.');
  }
}

/// A repository that refuses every check-in, as a cancelled or completed
/// session does.
class _RefusingCheckInRepository extends FakeSessionsRepository {
  _RefusingCheckInRepository({super.sessions});

  @override
  Future<SessionModel> checkIn({required String sessionId}) async {
    throw const ConflictFailure('This session is no longer open for check-in.');
  }
}

void main() {
  group('the record', () {
    testWidgets('names the session and both sides of it', (tester) async {
      await _pumpDetail(
        tester,
        FakeSessionsRepository(sessions: [session()]),
        _tutee,
      );

      expect(find.text('Second order ODEs'), findsOneWidget);
      // Names, not public ids. This row used to render the other party's
      // public_id because `SessionResponse` carried no display name for either
      // party, which showed a student a UUID instead of the person they were
      // about to meet. The API now projects both names and the unit's code and
      // title beside the ids.
      expect(find.text('Tutor'), findsOneWidget);
      expect(find.text('Okello Daniel'), findsOneWidget);
      expect(find.text(_tutor.publicId), findsNothing);
      expect(find.text('MAT 221 · Linear Algebra'), findsOneWidget);
      expect(find.text('1 hr'), findsOneWidget);
    });

    testWidgets('falls back to the public id when the other party is unnamed', (
      tester,
    ) async {
      // An account can exist without a display name. The row is about
      // identifying a person the reader is about to meet, so it shows the id
      // rather than leaving a labelled row empty -- but it is a fallback, not
      // the normal reading.
      final unnamed = SessionModel(
        id: 'session-1',
        tuteeId: _tutee.publicId,
        tutorId: _tutor.publicId,
        courseUnitId: 'unit-1',
        courseUnitCode: 'MAT 221',
        courseUnitName: 'Linear Algebra',
        topic: 'Second order ODEs',
        statusWire: 'scheduled',
        createdAt: DateTime.utc(2026, 3, 1, 8),
        scheduledStart: DateTime.utc(2026, 3, 2, 9),
        durationMinutes: 60,
      );
      await _pumpDetail(
        tester,
        FakeSessionsRepository(sessions: [unnamed]),
        _tutee,
      );

      expect(find.text('Tutor'), findsOneWidget);
      expect(find.text(_tutor.publicId), findsOneWidget);
    });

    testWidgets('a meeting link is copyable rather than tappable', (
      tester,
    ) async {
      // The app ships no link-opening dependency, and the agreed substitute for
      // in-app chat is a value the student hands to a browser.
      await _pumpDetail(
        tester,
        FakeSessionsRepository(
          sessions: [session(meetingLink: 'https://meet.peerpass.test/abc')],
        ),
        _tutee,
      );

      expect(find.byTooltip('Copy meeting link'), findsOneWidget);
      expect(find.text('https://meet.peerpass.test/abc'), findsOneWidget);
    });

    testWidgets('the selected on-campus venue is shown', (tester) async {
      await _pumpDetail(
        tester,
        FakeSessionsRepository(
          sessions: [
            session(meetingVenue: 'FCI Lab 1', meetingVenueDetail: 'Desk 3'),
          ],
        ),
        _tutee,
      );

      expect(find.text('Venue'), findsOneWidget);
      expect(find.text('FCI Lab 1 · Desk 3'), findsOneWidget);
    });

    testWidgets('a session that is not there says so and offers another try', (
      tester,
    ) async {
      await _pumpDetail(tester, _MissingSessionRepository(), _tutee);

      expect(
        find.text(
          const NotFoundFailure('That session could not be found.').message,
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('the pass', () {
    testWidgets('each party checks themselves in', (tester) async {
      await _pumpDetail(
        tester,
        FakeSessionsRepository(sessions: [session()]),
        _tutee,
      );

      expect(find.text("I'm here"), findsOneWidget);
      expect(find.text('Finish session'), findsNothing);
      expect(find.text('Are you both here?'), findsOneWidget);
    });

    testWidgets('a check-in waits for the other party', (tester) async {
      final repository = FakeSessionsRepository(sessions: [session()]);
      await _pumpDetail(tester, repository, _tutee);

      await tester.tap(find.text("I'm here"));
      await _settle(tester);

      expect(repository.checkedInSessionIds, [_sessionId]);
      expect(find.text("You're checked in"), findsOneWidget);
      // The other party is named, because "waiting" without a name is the
      // screen asking the student to guess who they are waiting for.
      expect(find.textContaining('Waiting for Okello Daniel'), findsOneWidget);
      expect(find.text("I'm here"), findsNothing);
    });

    testWidgets('the second check-in starts the session', (tester) async {
      final repository = FakeSessionsRepository(
        sessions: [session(tuteeCheckedInAt: '2026-03-04T09:05:00Z')],
      );
      await _pumpDetail(tester, repository, _tutor);

      await tester.tap(find.text("I'm here"));
      await _settle(tester);

      expect(find.text('Session in progress'), findsOneWidget);
      expect(find.text('Finish session'), findsOneWidget);
      // The tutor's timestamp is the one the fake recorded, not the student's.
      expect(repository.sessions.single.tutorCheckedInAt, isNotNull);
    });

    testWidgets('a refused check-in says so and keeps the button', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _RefusingCheckInRepository(sessions: [session()]),
        _tutee,
      );

      await tester.tap(find.text("I'm here"));
      await _settle(tester);

      expect(
        find.text(
          const ConflictFailure('This session is no longer open for check-in.')
              .message,
        ),
        findsOneWidget,
      );
      expect(find.text("I'm here"), findsOneWidget);
    });
  });

  group('finishing', () {
    SessionModel live({String? tutorFinishedAt, String? tuteeFinishedAt}) {
      return session(
        status: 'in_progress',
        startedAt: '2026-03-04T09:05:00Z',
        tutorCheckedInAt: '2026-03-04T09:05:00Z',
        tuteeCheckedInAt: '2026-03-04T09:07:00Z',
        tutorFinishedAt: tutorFinishedAt,
        tuteeFinishedAt: tuteeFinishedAt,
      );
    }

    testWidgets('the first finish waits for the other party', (tester) async {
      final repository = FakeSessionsRepository(sessions: [live()]);
      await _pumpDetail(tester, repository, _tutor);

      await tester.tap(find.text('Finish session'));
      await _settle(tester);
      // Finishing cannot be undone, so the tap asks first.
      expect(find.text('Finish this session?'), findsOneWidget);

      await tester.tap(find.text('Finish'));
      await _settle(tester);

      expect(repository.finishedSessionIds, [_sessionId]);
      expect(find.text("You're finished"), findsOneWidget);
      expect(find.textContaining('Waiting for Adongo Sarah'), findsOneWidget);
    });

    testWidgets('the second finish closes the session and offers a rating', (
      tester,
    ) async {
      final repository = FakeSessionsRepository(
        sessions: [live(tutorFinishedAt: '2026-03-04T10:00:00Z')],
      );
      await _pumpDetail(tester, repository, _tutee);

      await tester.tap(find.text('Finish session'));
      await _settle(tester);
      await tester.tap(find.text('Finish'));
      await _settle(tester);

      expect(
        repository.sessions.single.status,
        TutoringSessionStatus.completed,
      );
      expect(find.text('Rate this session'), findsOneWidget);
    });

    testWidgets('the confirmation can be dismissed', (tester) async {
      final repository = FakeSessionsRepository(sessions: [live()]);
      await _pumpDetail(tester, repository, _tutor);

      await tester.tap(find.text('Finish session'));
      await _settle(tester);
      await tester.tap(find.text('Keep going'));
      await _settle(tester);

      expect(repository.finishedSessionIds, isEmpty);
      expect(find.text('Finish session'), findsOneWidget);
    });
  });

  group('rating', () {
    testWidgets('a completed session offers the rating screen', (tester) async {
      await _pumpDetail(
        tester,
        FakeSessionsRepository(sessions: [session(status: 'completed')]),
        _tutee,
      );

      expect(find.text('Rate this session'), findsOneWidget);
    });

    testWidgets('a no-show is not dressed up as something to do', (
      tester,
    ) async {
      // A no-show is the case where a rating might be tempting and must not be.
      await _pumpDetail(
        tester,
        FakeSessionsRepository(sessions: [session(status: 'no_show')]),
        _tutee,
      );

      expect(find.text('Rate this session'), findsNothing);
      expect(find.textContaining('did not take place'), findsOneWidget);
    });

    testWidgets(
      'a completed session already rated by someone else says only that',
      (tester) async {
        // `is_rated` is true for both parties of a rated session, so telling a tutor
        // they have rated their own session would be a lie.
        await _pumpDetail(
          tester,
          FakeSessionsRepository(
            sessions: [session(status: 'completed', isRated: true)],
          ),
          _tutor,
        );

        expect(find.text('This session has been rated.'), findsOneWidget);
        expect(find.text('Rate this session'), findsNothing);
      },
    );

    testWidgets(
      'a tutor does not claim a rating before the student gives one',
      (tester) async {
        await _pumpDetail(
          tester,
          FakeSessionsRepository(sessions: [session(status: 'completed')]),
          _tutor,
        );

        expect(
          find.text('Waiting for the student to rate this session.'),
          findsOneWidget,
        );
        expect(find.text('This session has been rated.'), findsNothing);
      },
    );
  });

  testWidgets('a session opened with no back stack offers a way home', (
    tester,
  ) async {
    // The tutor lands here by `go` after confirming a help request, which
    // replaces the stack. The app bar's automatic back control therefore does not
    // appear, and without an explicit home control the tutor is stranded on the
    // session they just booked.
    final repository = FakeSessionsRepository(sessions: [session()])
      ..currentUser = _tutor.publicId;
    final router = GoRouter(
      initialLocation: AppRoutes.sessionDetailPath(_sessionId),
      routes: [
        GoRoute(
          path: AppRoutes.sessionDetailPath(_sessionId),
          builder: (context, state) =>
              const SessionDetailScreen(sessionId: _sessionId),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Text('Home after the session')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(repository, _tutor),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await _settle(tester);

    expect(find.byTooltip('Back to Home'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Home'));
    await _settle(tester);

    expect(find.text('Home after the session'), findsOneWidget);
  });

  testWidgets(
    'a rating given by the previous account is not shown to the next',
    (tester) async {
      // Two people share a handset in the pilot, and this controller outlives a
      // sign-out. The tutee's submission must not come back as the tutor's own
      // "you rated this" after the account changes.
      final repository = FakeSessionsRepository(
        sessions: [session(status: 'completed')],
      )..currentUser = _tutee.publicId;
      final container = _container(repository, _tutee);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SessionDetailScreen(sessionId: _sessionId),
          ),
        ),
      );
      await _settle(tester);

      container
          .read(sessionDetailProvider(_sessionId).notifier)
          .recordRating(
            RatingModel(
              id: 'rating-1',
              sessionId: _sessionId,
              raterId: _tutee.publicId,
              rateeId: _tutor.publicId,
              score: 5,
              comprehensionHelped: true,
              createdAt: DateTime.utc(2026, 3, 4, 9),
            ),
          );
      await _settle(tester);
      expect(find.text('You rated this 5 out of 5'), findsOneWidget);

      repository.currentUser = _tutor.publicId;
      container.read(sessionControllerProvider.notifier).signedIn(_tutor);
      await _settle(tester);

      expect(find.textContaining('You rated this'), findsNothing);
      expect(
        find.text('Waiting for the student to rate this session.'),
        findsOneWidget,
      );
    },
  );
}

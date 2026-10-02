import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/home/presentation/screens/home_screen.dart';

/// A student who has finished onboarding, so the router would let them stay here.
const UserProfile _enrolled = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 2,
);

/// The greeting the screen builds from the first name alone.
const String _greeting = 'Hello, Achieng';

/// The same account once they have been approved to teach.
const UserProfile _tutor = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student, UserRole.tutor},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 2,
);

/// A container to read the session through, plus the repository behind it.
typedef _Harness = ({
  ProviderContainer container,
  FakeAuthRepository repository,
});

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// Pumps home over a container holding [profile] as the signed-in account.
_Harness _harness(UserProfile profile) {
  final repository = FakeAuthRepository(
    session: profile,
    refreshToken: 'refresh',
  );
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier).signedIn(profile);
  return (container: container, repository: repository);
}

Future<void> _pumpHome(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('greets the student by the first name on their profile', (
    tester,
  ) async {
    await _pumpHome(tester, _harness(_enrolled));

    expect(find.text(_greeting), findsOneWidget);
    // The avatar is derived from the stored name rather than an upload: the
    // pilot stores no images, and a client-side upload would put a face in a
    // bucket the API does not describe.
    expect(
      find.descendant(of: find.byType(CircleAvatar), matching: find.text('AO')),
      findsOneWidget,
    );
  });

  testWidgets('shows which account is signed in', (tester) async {
    await _pumpHome(tester, _harness(_enrolled));

    expect(find.text('Signed in as ${_enrolled.email}'), findsOneWidget);
  });

  testWidgets('the sessions entry is live, not a promise', (tester) async {
    // Sessions are built, so the landing screen has to offer a way in. Marked
    // Soon, or hidden among the pending tiles, a working feature looks absent.
    final harness = _harness(_enrolled);
    await _pumpHome(tester, harness);

    expect(find.text('My sessions'), findsOneWidget);
    expect(find.text('Soon'), findsNothing);
  });

  testWidgets('tapping the sessions entry opens the sessions list', (
    tester,
  ) async {
    // Asserted through a real router, because the claim under test is a
    // navigation and a test without one would pass against a handler that
    // pushes nothing at all.
    final harness = _harness(_enrolled);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: AppRoutes.sessions,
          builder: (_, _) => const Scaffold(body: Text('Sessions list here')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('My sessions'));
    await _settle(tester);

    expect(find.text('Sessions list here'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('tapping the tutor entry opens the course unit picker', (
    tester,
  ) async {
    // Asserted through a real router, because the claim under test is a
    // navigation and a test without one would pass against a handler that pushes
    // nothing at all. Matching is built, so this entry is no longer a promise --
    // a working feature marked Soon is a working feature nobody can find.
    final harness = _harness(_enrolled);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: AppRoutes.matching,
          builder: (_, _) => const Scaffold(body: Text('Course units here')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Find a tutor'));
    await _settle(tester);

    expect(find.text('Course units here'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets(
    'the rail the shell supplies is shown, and its absence is silent',
    (tester) async {
      // The rail belongs to the tutors feature and reaches home as a widget, so
      // home's only job is to place it. Supplied, it appears; not supplied, there is
      // no gap and no placeholder, which is the state home's own tests are in.
      final harness = _harness(_enrolled);
      await _pumpHome(tester, harness);

      expect(find.text('Tutors at your university'), findsNothing);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const HomeScreen(
              // A bare marker, not a Scaffold: the rail is placed inside a
              // scrolling column, and a Scaffold there would ask for the height it
              // cannot have. The real rail sizes its own cards.
              tutorRail: Text('Tutors at your university'),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Tutors at your university'), findsOneWidget);
    },
  );

  testWidgets('a tutor is offered their certificate, and a student is not', (
    tester,
  ) async {
    // The entry is about the viewer's own banked hours, so it belongs to the
    // tutor. A student who tapped it would land on a screen whose honest answer
    // is that they have not applied yet.
    await _pumpHome(tester, _harness(_enrolled));

    expect(find.text('My certificate'), findsNothing);

    await _pumpHome(tester, _harness(_tutor));

    expect(find.text('My certificate'), findsOneWidget);
  });

  testWidgets('tapping the certificate entry opens the certificate screen', (
    tester,
  ) async {
    // Asserted through a real router, because the claim under test is a
    // navigation and a test without one would pass against a handler that pushes
    // nothing at all.
    final harness = _harness(_tutor);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: AppRoutes.certificate,
          builder: (_, _) =>
              const Scaffold(body: Text('Certificate screen here')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('My certificate'));
    await _settle(tester);

    expect(find.text('Certificate screen here'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('a tutor is told what is waiting on them, and a student is not', (
    tester,
  ) async {
    // The requests are the only entries on this screen about somebody else waiting
    // for something, so they go stale. A tutor who never learns they were chosen
    // is a tutor who never answers.
    await _pumpHome(tester, _harness(_enrolled));

    expect(find.text('Waiting on you'), findsNothing);

    await _pumpHome(tester, _harness(_tutor));

    expect(find.text('Waiting on you'), findsOneWidget);
  });

  testWidgets("the waiting entry comes before the tutor's own progress", (
    tester,
  ) async {
    // Ordering is the only thing that makes this entry get read. It is a decision
    // about a tutor scrolling, so it is asserted rather than left to the widget
    // order it happens to have.
    await _pumpHome(tester, _harness(_tutor));

    final waiting = tester.getTopLeft(find.text('Waiting on you')).dy;
    final certificate = tester.getTopLeft(find.text('My certificate')).dy;

    expect(waiting, lessThan(certificate));
  });

  testWidgets('tapping it opens the list of requests awaiting an answer', (
    tester,
  ) async {
    // Through a real router, because the claim under test is a navigation.
    final harness = _harness(_tutor);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: AppRoutes.tutorRequests,
          builder: (_, _) => const Scaffold(body: Text('Waiting screen here')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Waiting on you'));
    await _settle(tester);

    expect(find.text('Waiting screen here'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}

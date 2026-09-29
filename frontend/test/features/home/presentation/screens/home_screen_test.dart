import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// A container to read the session through, plus the repository behind it.
typedef _Harness = ({ProviderContainer container, FakeAuthRepository repository});

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// Pumps home over a container holding [profile] as the signed-in account.
_Harness _harness(UserProfile profile) {
  final repository = FakeAuthRepository(session: profile, refreshToken: 'refresh');
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
      find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.text('AO'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows which account is signed in', (tester) async {
    await _pumpHome(tester, _harness(_enrolled));

    expect(
      find.text('Signed in as ${_enrolled.email}'),
      findsOneWidget,
    );
  });

  testWidgets('the two pending tiles are marked Soon and lead nowhere', (
    tester,
  ) async {
    // There is no tutor list and no booking screen in this release, so a tile
    // that navigated would take a student somewhere that does not exist. The
    // claim is checked by pressing both: the screen stays mounted, the greeting
    // stays, and the session is untouched. These tests run without a router, so
    // a tile that reached for `context.go` would have nothing to go with and the
    // press would throw rather than pass quietly.
    final harness = _harness(_enrolled);
    await _pumpHome(tester, harness);

    expect(find.text('Find a tutor'), findsOneWidget);
    expect(find.text('Book a session'), findsOneWidget);
    expect(
      find.text('Soon'),
      findsNWidgets(2),
      reason: 'both tiles promise something the app cannot do yet',
    );

    await tester.tap(find.text('Find a tutor'));
    await _settle(tester);
    await tester.tap(find.text('Book a session'));
    await _settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(_greeting), findsOneWidget);
    expect(
      harness.container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
  });

  testWidgets('tapping sign out in the app bar ends the session', (tester) async {
    // Regression. `onPressed` is a `VoidCallback`, so a handler of
    // `() => ref.read(signOutControllerProvider)` evaluated the read, discarded
    // the function it returned, and signed nobody out while still looking like
    // it worked. The button has to be the thing under test, not the provider.
    final harness = _harness(_enrolled);
    await _pumpHome(tester, harness);
    expect(
      harness.container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );

    await tester.tap(find.byTooltip('Sign out'));
    await _settle(tester);

    final session = harness.container.read(sessionControllerProvider);
    expect(session.status, SessionStatus.unauthenticated);
    expect(session.profile, isNull);
    // The token is discarded on the device before the session is recorded as
    // ended, so a request that never reaches the server still leaves this device
    // signed out.
    expect(harness.repository.session, isNull);
    expect(harness.repository.refreshToken, isNull);
  });
}

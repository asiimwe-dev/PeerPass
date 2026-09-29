import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/app.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/app/splash_screen.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';

const String _signedOutText = 'Sign in';

/// The greeting home builds from the stored name. Asserting on this rather than
/// on a placeholder string means the test fails if the profile stopped reaching
/// the screen, which is the thing it is actually about.
const String _homeText = 'Hello, Achieng';

/// A student who has finished onboarding.
const UserProfile _enrolled = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: {UserRole.student},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 2,
);

/// A student who has signed up but has not run the wizard.
const UserProfile _freshAccount = UserProfile(
  publicId: 'user-2',
  email: 'newcomer@must.ac.ug',
  roles: {UserRole.student},
);

/// A repository whose restore stays pending until the test releases it.
///
/// Needed to observe the window where the auth status is genuinely unknown. The
/// fake resolves within a microtask, so the app would pass straight through
/// splash and the redirect would never be seen mid-flight.
///
/// Extends the fake rather than implementing the contract, so it keeps answering
/// sign-in and profile calls if a test needs them.
class _GatedAuthRepository extends FakeAuthRepository {
  final Completer<UserProfile?> _gate = Completer<UserProfile?>();

  void release({UserProfile? profile}) => _gate.complete(profile);

  @override
  Future<UserProfile?> restoreSession() => _gate.future;
}

/// A repository that fails the cold-start check the way a dropped connection
/// does, rather than reporting signed out.
class _OfflineAuthRepository extends FakeAuthRepository {
  @override
  Future<UserProfile?> restoreSession() async {
    throw const NetworkFailure();
  }
}

FakeAuthRepository _signedIn({UserProfile? profile}) {
  return FakeAuthRepository(
    session: profile ?? _enrolled,
    refreshToken: 'refresh',
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lands on sign-in when there is no stored session', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const PeerPassApp(),
      ),
    );
    await _settle(tester);

    expect(find.text(_signedOutText), findsOneWidget);
  });

  testWidgets('lands on home when a stored session restores', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_signedIn()),
        ],
        child: const PeerPassApp(),
      ),
    );
    await _settle(tester);

    expect(find.text(_homeText), findsOneWidget);
  });

  testWidgets('holds on splash while the session is still unknown', (
    tester,
  ) async {
    final repository = _GatedAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const PeerPassApp(),
      ),
    );
    await tester.pump();

    // The restore has not returned, so the app must still be on splash rather
    // than flashing sign-in at a returning user.
    expect(find.byType(SplashScreen), findsOneWidget);

    repository.release();
    await _settle(tester);

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text(_signedOutText), findsOneWidget);
  });

  testWidgets('a new account is sent to onboarding rather than home', (
    tester,
  ) async {
    // The whole point of onboarding existing: signing up gets you a session, and
    // a session alone is not a usable account. Landing such a student on home
    // would show them a shell with nothing in it and no route to filling it in.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _signedIn(profile: _freshAccount),
          ),
        ],
        child: const PeerPassApp(),
      ),
    );
    await _settle(tester);

    expect(find.text(_homeText), findsNothing);
    expect(find.text('What is your name?'), findsOneWidget);
  });

  testWidgets('a network failure keeps the user on splash with a way out', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_OfflineAuthRepository()),
        ],
        child: const PeerPassApp(),
      ),
    );
    await _settle(tester);

    // Not signed in, and not stranded: the splash screen says what happened and
    // offers a retry, because a student on a train is not signed out.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an auth change redirects without the screen asking', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_signedIn()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PeerPassApp(),
      ),
    );
    await _settle(tester);
    expect(find.text(_homeText), findsOneWidget);

    await container.read(authControllerProvider).signOut();
    await _settle(tester);

    expect(find.text(_signedOutText), findsOneWidget);
    expect(find.text(_homeText), findsNothing);
  });

  testWidgets('a deep link to home is sent to sign-in when signed out', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const PeerPassApp(),
      ),
    );
    await _settle(tester);

    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go(AppRoutes.home);
    await _settle(tester);

    expect(find.text(_signedOutText), findsOneWidget);
  });
}

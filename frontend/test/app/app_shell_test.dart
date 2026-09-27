import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ulearn/app/app.dart';
import 'package:ulearn/app/router.dart';
import 'package:ulearn/app/splash_screen.dart';
import 'package:ulearn/core/models/user_role.dart';
import 'package:ulearn/core/storage/token_store.dart';
import 'package:ulearn/features/auth/data/datasources/in_memory_auth_datasource.dart';
import 'package:ulearn/features/auth/data/models/auth_session.dart';
import 'package:ulearn/features/auth/data/repositories/auth_repository.dart';
import 'package:ulearn/features/auth/data/repositories/in_memory_auth_repository.dart';
import 'package:ulearn/features/auth/presentation/providers/auth_providers.dart';

const String _signedOutText = 'Sign in is not implemented yet.';
const String _homeText = 'Home is not implemented yet.';

const AuthSession _tutor = AuthSession(
  publicId: 'user-1',
  email: 'tutor@ug.ac.ug',
  roles: {UserRole.tutor},
);

/// A repository whose restore stays pending until the test releases it.
///
/// Needed to observe the window where the auth status is genuinely unknown.
/// The in-memory datasource resolves within a microtask, so the app would pass
/// straight through splash and the redirect would never be seen mid-flight.
class _GatedAuthRepository implements AuthRepository {
  final Completer<AuthSession?> _gate = Completer<AuthSession?>();

  void release({AuthSession? session}) => _gate.complete(session);

  @override
  Future<AuthSession?> restoreSession() => _gate.future;

  @override
  Future<void> signOut() async {}
}

/// A token store holding a session, so the in-memory datasource reports one.
TokenStore _signedInTokenStore() {
  return InMemoryTokenStore(accessToken: 'access', refreshToken: 'refresh');
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lands on sign-in when there is no stored session', (
    tester,
  ) async {
    final datasource = InMemoryAuthDatasource(tokenStore: InMemoryTokenStore());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            InMemoryAuthRepository(datasource),
          ),
        ],
        child: const UlearnApp(),
      ),
    );
    await _settle(tester);

    expect(find.text(_signedOutText), findsOneWidget);
  });

  testWidgets('lands on home when a stored session restores', (tester) async {
    final datasource = InMemoryAuthDatasource(
      session: _tutor,
      tokenStore: _signedInTokenStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            InMemoryAuthRepository(datasource),
          ),
        ],
        child: const UlearnApp(),
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
        child: const UlearnApp(),
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

  testWidgets('an auth change redirects without the screen asking', (
    tester,
  ) async {
    final datasource = InMemoryAuthDatasource(
      session: _tutor,
      tokenStore: _signedInTokenStore(),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          InMemoryAuthRepository(datasource),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const UlearnApp()),
    );
    await _settle(tester);
    expect(find.text(_homeText), findsOneWidget);

    await container.read(authControllerProvider.notifier).signOut();
    await _settle(tester);

    expect(find.text(_signedOutText), findsOneWidget);
    expect(find.text(_homeText), findsNothing);
  });

  testWidgets('a deep link to home is sent to sign-in when signed out', (
    tester,
  ) async {
    final datasource = InMemoryAuthDatasource(tokenStore: InMemoryTokenStore());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            InMemoryAuthRepository(datasource),
          ),
        ],
        child: const UlearnApp(),
      ),
    );
    await _settle(tester);

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(AppRoutes.home);
    await _settle(tester);

    expect(find.text(_signedOutText), findsOneWidget);
  });
}

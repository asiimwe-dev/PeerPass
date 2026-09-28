import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/features/auth/data/models/auth_session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';

/// Whether the app knows who is signed in.
enum AuthStatus {
  /// Stored tokens have not been checked yet. The router holds here rather than
  /// showing sign-in, so a returning user is not flashed the sign-in screen
  /// before landing on their home screen.
  unknown,

  authenticated,

  unauthenticated,
}

@immutable
class AuthState {
  const AuthState({required this.status, this.session});

  const AuthState.unknown() : status = AuthStatus.unknown, session = null;

  const AuthState.signedOut()
    : status = AuthStatus.unauthenticated,
      session = null;

  const AuthState.signedIn(this.session) : status = AuthStatus.authenticated;

  final AuthStatus status;

  final AuthSession? session;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState && other.status == status && other.session == session;

  @override
  int get hashCode => Object.hash(status, session);

  @override
  String toString() => 'AuthState($status)';
}

/// The auth contract, overridden at startup with the chosen implementation.
///
/// Throwing rather than defaulting keeps a missing override loud: a silent fake
/// default would let a build ship pointed at nothing.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError(
    'authRepositoryProvider must be overridden in ProviderScope.',
  ),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Owns the session lifecycle for the shell.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    unawaited(_restore());
    return const AuthState.unknown();
  }

  /// Ends the session and returns to the signed-out state.
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthState.signedOut();
  }

  Future<void> _restore() async {
    try {
      final session = await ref.read(authRepositoryProvider).restoreSession();
      state = session == null
          ? const AuthState.signedOut()
          : AuthState.signedIn(session);
    } on Object {
      // An unreachable API on cold start must not strand the app on the splash
      // route with no way forward, so an unresolvable session is treated as
      // signed out and the user signs in again.
      state = const AuthState.signedOut();
    }
  }
}

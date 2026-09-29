import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';

/// Ends the session, from anywhere in the app.
///
/// Exists because signing out is the one session action a screen outside the auth
/// feature needs, and the only way it may reach auth is through the repository
/// contract. Reaching for the auth screens' controller instead would be exactly
/// the cross-feature presentation import the architecture forbids.
///
/// The two steps are the same two the auth screens perform, and deliberately in
/// that order: the token must be discarded on the device first, so that a failure
/// to reach the server still leaves this device signed out. Recording the session
/// as ended before the call would mean a student whose request timed out was
/// still holding a live refresh token.
final signOutControllerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(authRepositoryProvider).signOut();
    ref.read(sessionControllerProvider.notifier).signedOut();
  };
});

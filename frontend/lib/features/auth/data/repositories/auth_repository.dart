import 'package:peerpass/features/auth/data/models/auth_session.dart';

/// The authentication contract the rest of the client depends on.
///
/// Sign-in and registration are intentionally absent for now: the shell only
/// needs to know whether a session can be restored, and adding credential
/// handling before the API's auth endpoints exist would mean shipping
/// behaviour with nothing to verify it against.
abstract interface class AuthRepository {
  /// The session implied by stored tokens, or null when signed out.
  ///
  /// Called on cold start. Implementations must clear a rejected refresh
  /// token rather than surfacing an error, because a token the server no
  /// longer honours is the definition of signed out.
  Future<AuthSession?> restoreSession();

  /// Discards the stored session on this device.
  Future<void> signOut();
}

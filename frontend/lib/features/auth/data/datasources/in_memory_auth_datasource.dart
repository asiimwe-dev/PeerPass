import 'package:peerpass/core/storage/token_store.dart';
import 'package:peerpass/features/auth/data/models/auth_session.dart';

/// In-memory stand-in for the auth endpoints.
///
/// Until the API exposes sign-in, this is what the running app resolves, so the
/// shell boots to the signed-out route and the router's guard can be exercised
/// end to end. A session can be injected to simulate a returning user, which is
/// how the smoke test covers the authenticated branch.
class InMemoryAuthDatasource {
  InMemoryAuthDatasource({this.session, TokenStore? tokenStore})
    // An in-memory store is the default because widget tests have no platform
    // channel to serve a real one.
    : _tokenStore = tokenStore ?? InMemoryTokenStore();

  /// The session to report, or null to report signed out.
  AuthSession? session;

  final TokenStore _tokenStore;

  Future<AuthSession?> restoreSession() async {
    // A real implementation would present the refresh token and could find a
    // stored token the server has since rotated away. The in-memory token store
    // is always empty unless a test writes to it, so the presence check stands
    // in for that round trip.
    final hasToken = await _tokenStore.readRefreshToken() != null;
    return hasToken ? session : null;
  }

  Future<void> clearTokens() => _tokenStore.clear();
}

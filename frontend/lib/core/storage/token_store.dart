import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the access and refresh tokens.
///
/// Abstracted because the tests must run without a platform channel, and
/// because a future pass moves the refresh token behind the platform's
/// keystore-backed credential store. [InMemoryTokenStore] satisfies both.
abstract interface class TokenStore {
  /// The short-lived bearer token sent on every authenticated request.
  Future<String?> readAccessToken();

  /// The long-lived token used to obtain a new access token.
  Future<String?> readRefreshToken();

  /// Replaces both tokens.
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  });

  /// Forgets the session.
  ///
  /// Called on sign-out and whenever a refresh is rejected, because a rejected
  /// refresh means the server no longer honours this session.
  Future<void> clear();
}

/// [TokenStore] backed by the platform keystore.
///
/// Tokens are credentials, so they never go in `shared_preferences`, which is
/// plain text on disk. Android is backed by the EncryptedSharedPreferences
/// keystore and iOS by the keychain.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  static const String _accessKey = 'ulearn_access_token';
  static const String _refreshKey = 'ulearn_refresh_token';
}

/// Non-persistent [TokenStore] for tests and for the fake data sources.
///
/// Widget tests have no platform channel, so a real store would throw. Holding
/// the tokens in memory keeps a test from leaking a session between cases.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }
}

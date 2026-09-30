import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the access and refresh tokens.
///
/// Abstracted because the tests must run without a platform channel, and
/// because the two tokens are not stored the same way: the access token lives
/// in memory and the refresh token lives in the platform keystore. The split is
/// the interface, not an implementation detail, because every implementation is
/// required to have it.
abstract interface class TokenStore {
  /// The short-lived bearer token sent on every authenticated request.
  ///
  /// Null after a cold start, always. A token with a fifteen minute lifetime has
  /// nothing to offer a process that has just begun, and the first thing the app
  /// does is spend the refresh token to get a new one. Holding it in memory also
  /// means a heap dump taken while the app is open does not hand over a usable
  /// credential, which writing it to disk would.
  Future<String?> readAccessToken();

  /// The long-lived token used to obtain a new access token.
  ///
  /// The only token that survives the process, and therefore the one that is
  /// worth protecting with the platform's credential storage.
  Future<String?> readRefreshToken();

  /// Replaces both tokens.
  ///
  /// Both are replaced together because they are minted together, and a pair
  /// where the refresh token is older than the access token is a state the
  /// server has no way to describe.
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

/// The keystore-backed storage the refresh token is written to.
///
/// An interface rather than a direct dependency on `FlutterSecureStorage` for one
/// reason: a widget test has no platform channel, and the interesting property
/// of [SecureTokenStore] -- that the access token stays in memory while the
/// refresh token does not -- cannot be tested against a real keystore. A test
/// using a fake can assert on exactly what was persisted; a test against the
/// platform can only assert that it did not throw.
abstract interface class SecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [SecureStorage] over the platform's own credential store.
///
/// Android is backed by the EncryptedSharedPreferences keystore and iOS by the
/// keychain. A token never goes in `shared_preferences`, which is plain text on
/// disk.
class PlatformSecureStorage implements SecureStorage {
  const PlatformSecureStorage([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// [TokenStore] backed by the platform keystore, for the refresh token only.
///
/// The refresh token never goes in `shared_preferences`, which is plain text on
/// disk. The access token is held in a field and never written anywhere.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([SecureStorage? storage])
    : _storage = storage ?? const PlatformSecureStorage();

  final SecureStorage _storage;

  /// The access token, in memory only.
  ///
  /// Deliberately a plain field rather than anything the platform persists: the
  /// requirement is that it is gone when the process is, and a field makes that
  /// true by construction instead of by remembering to clear it.
  String? _accessToken;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() => _storage.read(_refreshKey);

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    await _storage.write(_refreshKey, refreshToken);
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    await _storage.delete(_refreshKey);
  }

  static const String _refreshKey = 'peerpass_refresh_token';
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

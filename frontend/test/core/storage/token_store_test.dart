import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/storage/token_store.dart';

/// [SecureTokenStore] is the only store that touches the platform channel, and
/// widget tests have none. [InMemoryTokenStore] stands in for the secure
/// storage underneath it while the split between memory and disk is exercised
/// for real: that split is the whole point of the store, and a test using only
/// the in-memory implementation would pass whether or not it existed.
void main() {
  group('SecureTokenStore', () {
    late _FakeSecureStorage storage;
    late SecureTokenStore store;

    setUp(() {
      storage = _FakeSecureStorage();
      store = SecureTokenStore(storage);
    });

    test('a written pair is readable', () async {
      await store.write(accessToken: 'access-1', refreshToken: 'refresh-1');

      expect(await store.readAccessToken(), 'access-1');
      expect(await store.readRefreshToken(), 'refresh-1');
    });

    test('the access token never reaches the platform store', () async {
      await store.write(accessToken: 'access-1', refreshToken: 'refresh-1');

      expect(storage.values.keys, ['peerpass_refresh_token']);
      expect(storage.values['peerpass_refresh_token'], 'refresh-1');
      expect(storage.values.values, isNot(contains('access-1')));
    });

    test('a new store over the same storage has no access token', () async {
      // The cold-start case, and the reason [SecureTokenStore.readAccessToken]
      // is allowed to return null. The refresh token survived the restart and
      // the access token did not, which is the intended arrangement: fifteen
      // minutes of a token the app is not running does not need protecting, and
      // a heap dump of a running process should not yield one.
      await store.write(accessToken: 'access-1', refreshToken: 'refresh-1');

      final afterRestart = SecureTokenStore(storage);

      expect(await afterRestart.readAccessToken(), isNull);
      expect(await afterRestart.readRefreshToken(), 'refresh-1');
    });

    test('writing a second pair replaces the first, leaving no stale refresh', () async {
      await store.write(accessToken: 'access-1', refreshToken: 'refresh-1');
      await store.write(accessToken: 'access-2', refreshToken: 'refresh-2');

      expect(await store.readAccessToken(), 'access-2');
      expect(await store.readRefreshToken(), 'refresh-2');
      expect(storage.values.values, hasLength(1));
    });

    test('clear forgets both tokens', () async {
      await store.write(accessToken: 'access-1', refreshToken: 'refresh-1');

      await store.clear();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(storage.values, isEmpty);
    });
  });

  group('InMemoryTokenStore', () {
    test('a new instance does not inherit a previous session', () async {
      final first = InMemoryTokenStore();
      await first.write(accessToken: 'access-1', refreshToken: 'refresh-1');

      final second = InMemoryTokenStore();

      expect(await second.readAccessToken(), isNull);
      expect(await second.readRefreshToken(), isNull);
    });
  });
}

/// Stands in for the platform keystore.
///
/// Records what was written so the test can assert on what the store chose to
/// persist, which is the property under test. A real implementation would talk
/// to a platform channel that does not exist in a unit test.
class _FakeSecureStorage implements SecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

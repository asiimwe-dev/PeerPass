import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

final sessionCacheProvider = Provider<SessionCache?>((ref) => null);

/// Encrypted, bounded cache for read-only session history.
class SessionCache {
  SessionCache({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _boxName = 'peerpass_sessions';
  static const _keyName = 'peerpass_hive_key';
  static const _payloadKey = 'payload';
  static const _storedAtKey = 'stored_at';
  static const _myRequestsPayloadKey = 'my_requests_payload';
  static const _myRequestsStoredAtKey = 'my_requests_stored_at';
  static const _awaitingRequestsPayloadKey = 'awaiting_requests_payload';
  static const _awaitingRequestsStoredAtKey = 'awaiting_requests_stored_at';
  static const _profileKey = 'last_profile';
  static const _topTutorsPrefix = 'top_tutors::';
  static const _universityKey = 'reference_universities';
  static const _facultyPrefix = 'reference_faculty::';
  static const _maxAge = Duration(hours: 24);
  static const _railMaxAge = Duration(days: 7);
  static const _referenceMaxAge = Duration(days: 30);

  final FlutterSecureStorage _secureStorage;
  late final Box<String> _box;
  String? _accountId;

  String? get accountId => _accountId;

  /// Switches the cache namespace before authenticated reads begin.
  ///
  /// A namespace is captured at the start of each operation, so a response
  /// finishing after sign-out cannot write into the next account's cache.
  void activateAccount(String accountId) {
    if (accountId.isEmpty || accountId == _accountId) return;
    _accountId = accountId;
  }

  void deactivateAccount() {
    _accountId = null;
  }

  Future<void> open() async {
    await Hive.initFlutter();
    final existing = await _secureStorage.read(key: _keyName);
    final key = existing == null
        ? Hive.generateSecureKey()
        : base64Url.decode(existing);
    if (existing == null) {
      await _secureStorage.write(key: _keyName, value: base64UrlEncode(key));
    }
    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  /// The last account this device signed in to, as the API last described it.
  ///
  /// Deliberately not account-scoped: at cold start the app has no account id
  /// yet, and the whole point of the snapshot is to know whose account it is
  /// before the server can be reached. Only the most recent account is kept,
  /// which is what "the last session on this handset" means.
  Future<Map<String, dynamic>?> readProfile() async {
    final payload = _box.get(_profileKey);
    if (payload == null) return null;
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  Future<void> writeProfile(Map<String, dynamic> profile) async {
    await _box.put(_profileKey, jsonEncode(profile));
  }

  Future<void> clearProfile() => _box.delete(_profileKey);

  /// The last discovery rail shown to this account, for one unit filter.
  ///
  /// Keyed by account rather than by university because the API derives the
  /// university from the caller's token. A rail kept under the caller's own
  /// namespace is the one answer the server would give them, not a guess based
  /// on an id the client supplied.
  Future<List<Map<String, dynamic>>?> readTopTutors({
    String? courseUnitId,
    String? accountId,
  }) async {
    final account = accountId ?? _accountId;
    if (account == null) return null;
    final base = _scopedKey(account, _railKey(courseUnitId));
    return await _readList(
      '$base::payload',
      '$base::stored_at',
      maxAge: _railMaxAge,
    );
  }

  Future<void> writeTopTutors(
    List<Map<String, dynamic>> tutors, {
    String? courseUnitId,
    String? accountId,
  }) async {
    final account = accountId ?? _accountId;
    if (account == null) return;
    final base = _scopedKey(account, _railKey(courseUnitId));
    await _writeList('$base::payload', '$base::stored_at', tutors);
  }

  /// The university catalogue last read, so a profile can name its university
  /// before the network answers.
  ///
  /// Reference data is public, so this is not account-scoped and survives a
  /// sign-out. It is still bounded: a catalogue nobody has read in a month is
  /// not a better answer than asking the server.
  Future<List<Map<String, dynamic>>?> readUniversities() => _readList(
    '$_universityKey::payload',
    '$_universityKey::stored_at',
    maxAge: _referenceMaxAge,
  );

  Future<void> writeUniversities(List<Map<String, dynamic>> universities) =>
      _writeList(
        '$_universityKey::payload',
        '$_universityKey::stored_at',
        universities,
      );

  Future<List<Map<String, dynamic>>?> readFaculties(String universityId) {
    final base = '$_facultyPrefix$universityId';
    return _readList(
      '$base::payload',
      '$base::stored_at',
      maxAge: _referenceMaxAge,
    );
  }

  Future<void> writeFaculties(
    String universityId,
    List<Map<String, dynamic>> faculties,
  ) {
    final base = '$_facultyPrefix$universityId';
    return _writeList('$base::payload', '$base::stored_at', faculties);
  }

  Future<List<Map<String, dynamic>>?> readSessions() async {
    final keys = _keys(_payloadKey, _storedAtKey);
    if (keys == null) return null;
    return await _readList(keys.$1, keys.$2);
  }

  Future<void> writeSessions(List<Map<String, dynamic>> sessions) async {
    final keys = _keys(_payloadKey, _storedAtKey);
    if (keys == null) return;
    await _writeList(keys.$1, keys.$2, sessions);
  }

  Future<List<Map<String, dynamic>>?> readHelpRequests({
    required bool awaitingTutor,
  }) async {
    final payloadKey = awaitingTutor
        ? _awaitingRequestsPayloadKey
        : _myRequestsPayloadKey;
    final storedAtKey = awaitingTutor
        ? _awaitingRequestsStoredAtKey
        : _myRequestsStoredAtKey;
    final keys = _keys(payloadKey, storedAtKey);
    if (keys == null) return null;
    return await _readList(keys.$1, keys.$2);
  }

  Future<void> writeHelpRequests(
    List<Map<String, dynamic>> requests, {
    required bool awaitingTutor,
  }) async {
    final payloadKey = awaitingTutor
        ? _awaitingRequestsPayloadKey
        : _myRequestsPayloadKey;
    final storedAtKey = awaitingTutor
        ? _awaitingRequestsStoredAtKey
        : _myRequestsStoredAtKey;
    final keys = _keys(payloadKey, storedAtKey);
    if (keys == null) return;
    await _writeList(keys.$1, keys.$2, requests);
  }

  Future<List<Map<String, dynamic>>?> _readList(
    String payloadKey,
    String storedAtKey, {
    Duration maxAge = _maxAge,
  }) async {
    final storedAt = _box.get(storedAtKey);
    final payload = _box.get(payloadKey);
    if (storedAt == null || payload == null) return null;
    final timestamp = DateTime.tryParse(storedAt);
    if (timestamp == null ||
        DateTime.now().toUtc().difference(timestamp.toUtc()) > maxAge) {
      await _box.delete(payloadKey);
      await _box.delete(storedAtKey);
      return null;
    }
    final decoded = jsonDecode(payload);
    if (decoded is! List) return null;
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<void> _writeList(
    String payloadKey,
    String storedAtKey,
    List<Map<String, dynamic>> rows,
  ) async {
    await _box.put(payloadKey, jsonEncode(rows));
    await _box.put(storedAtKey, DateTime.now().toUtc().toIso8601String());
  }

  Future<void> clear() async {
    final account = _accountId;
    if (account != null) {
      for (final key in [
        _payloadKey,
        _storedAtKey,
        _myRequestsPayloadKey,
        _myRequestsStoredAtKey,
        _awaitingRequestsPayloadKey,
        _awaitingRequestsStoredAtKey,
      ]) {
        await _box.delete(_scopedKey(account, key));
      }
      // The rail has one key per unit filter, so the set is discovered rather
      // than listed. A filter this device has never used has no key to remove.
      final railPrefix = _scopedKey(account, _topTutorsPrefix);
      for (final key in _box.keys.toList()) {
        if (key is String && key.startsWith(railPrefix)) {
          await _box.delete(key);
        }
      }
    }
    // The snapshot is the handset's last account, not the namespace's, so it is
    // cleared even when no account was active to scope the rest of the removal.
    await _box.delete(_profileKey);
  }

  (String, String)? _keys(String payloadKey, String storedAtKey) {
    final account = _accountId;
    if (account == null) return null;
    return (_scopedKey(account, payloadKey), _scopedKey(account, storedAtKey));
  }

  String _railKey(String? courseUnitId) =>
      '$_topTutorsPrefix${courseUnitId ?? 'all'}';

  String _scopedKey(String account, String key) => '$account::$key';
}

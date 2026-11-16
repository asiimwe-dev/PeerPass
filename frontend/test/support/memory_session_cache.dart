import 'package:peerpass/core/storage/session_cache.dart';

/// In-memory [SessionCache] for tests that need a saved device state.
///
/// The real cache is Hive plus a platform keystore, neither of which exists in a
/// widget test. Only the behaviour the app depends on is modelled: a profile
/// snapshot, a per-account rail keyed by unit, and the reference lists. A test
/// that asserts on the *cache* itself must still use the real class; this one is
/// for the auth and discovery paths that merely read it.
class MemorySessionCache extends SessionCache {
  // A private field behind a readable named parameter is the point here.
  // ignore: prefer_initializing_formals
  MemorySessionCache({Map<String, dynamic>? profile}) : _profile = profile;

  String? _account;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>>? _sessions;
  List<Map<String, dynamic>>? _universities;
  final Map<String, List<Map<String, dynamic>>> _faculties = {};
  final Map<String, List<Map<String, dynamic>>> _rails = {};

  @override
  String? get accountId => _account;

  @override
  void activateAccount(String accountId) {
    if (accountId.isEmpty) return;
    _account = accountId;
  }

  @override
  void deactivateAccount() => _account = null;

  @override
  Future<Map<String, dynamic>?> readProfile() async => _profile;

  @override
  Future<void> writeProfile(Map<String, dynamic> profile) async {
    _profile = profile;
  }

  @override
  Future<void> clearProfile() async {
    _profile = null;
  }

  @override
  Future<void> clear() async {
    _profile = null;
    _sessions = null;
    _rails.clear();
  }

  @override
  Future<List<Map<String, dynamic>>?> readSessions() async => _sessions;

  @override
  Future<void> writeSessions(List<Map<String, dynamic>> sessions) async {
    _sessions = sessions;
  }

  @override
  Future<List<Map<String, dynamic>>?> readTopTutors({
    String? courseUnitId,
    String? accountId,
  }) async {
    return _rails[_railKey(courseUnitId, accountId ?? _account)];
  }

  @override
  Future<void> writeTopTutors(
    List<Map<String, dynamic>> tutors, {
    String? courseUnitId,
    String? accountId,
  }) async {
    _rails[_railKey(courseUnitId, accountId ?? _account)] = tutors;
  }

  @override
  Future<List<Map<String, dynamic>>?> readUniversities() async => _universities;

  @override
  Future<void> writeUniversities(
    List<Map<String, dynamic>> universities,
  ) async {
    _universities = universities;
  }

  @override
  Future<List<Map<String, dynamic>>?> readFaculties(
    String universityId,
  ) async => _faculties[universityId];

  @override
  Future<void> writeFaculties(
    String universityId,
    List<Map<String, dynamic>> faculties,
  ) async {
    _faculties[universityId] = faculties;
  }

  String _railKey(String? courseUnitId, String? accountId) =>
      '${accountId ?? 'signed-out'}::${courseUnitId ?? 'all'}';
}

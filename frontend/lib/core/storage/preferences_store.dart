import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive preferences.
///
/// Explicitly not for credentials: anything secret belongs in
/// `core/storage/token_store.dart`, which is backed by the platform keystore.
/// This holds user-visible choices that are safe to read in plaintext on a
/// shared or backed-up device.
///
/// Reads are synchronous because `SharedPreferences` keeps a cache in memory
/// once `getInstance` has resolved; only writes touch the platform channel.
class PreferencesStore {
  const PreferencesStore(this._preferences);

  /// Loads the platform store.
  ///
  /// Async because the platform channel has to answer before the first frame.
  /// Construct this once during startup and reuse it.
  static Future<PreferencesStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    return PreferencesStore(preferences);
  }

  final SharedPreferences _preferences;

  /// Whether the student has dismissed the one-time introduction.
  bool hasSeenIntroduction() =>
      _preferences.getBool(_seenIntroductionKey) ?? false;

  Future<void> markIntroductionSeen() =>
      _preferences.setBool(_seenIntroductionKey, true);

  /// The course unit last viewed, used to restore the matching screen.
  String? readLastViewedUnitId() => _preferences.getString(_lastViewedUnitKey);

  Future<void> writeLastViewedUnitId(String unitId) =>
      _preferences.setString(_lastViewedUnitKey, unitId);

  static const String _seenIntroductionKey = 'ulearn.seen_introduction';
  static const String _lastViewedUnitKey = 'ulearn.last_viewed_unit_id';
}

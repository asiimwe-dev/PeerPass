import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/academic_fallback.dart';
import 'package:peerpass/core/models/course_unit_option.dart';
import 'package:peerpass/core/models/subject.dart';
import 'package:peerpass/core/models/university_option.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/storage/session_cache.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';

/// The auth operations, as calls the screens can make.
///
/// Performs authentication against the repository and records the outcome in
/// [SessionController]. It owns no session state of its own, so "who is signed
/// in" has exactly one home regardless of whether it was established by a
/// sign-in, a sign-up, a profile update, or a cold-start restore.
///
/// A plain [Provider] rather than a [Notifier]: it exposes no value of its own,
/// and a notifier that never does is one pretending to be something it is not.
/// Its single piece of behaviour is starting the cold-start check the first time
/// anything reads it, which is why the body is not a bare constructor.
final authControllerProvider = Provider<AuthController>((ref) {
  final controller = AuthController(ref)..startRestore();
  return controller;
});

class AuthController {
  AuthController(this._ref);

  final Ref _ref;
  int _operation = 0;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  SessionController get _session =>
      _ref.read(sessionControllerProvider.notifier);

  SessionCache? get _cache => _ref.read(sessionCacheProvider);

  /// Signs in and adopts the account the API returns.
  Future<void> signIn({required String email, required String password}) async {
    final operation = ++_operation;
    final profile = await _repository.signIn(email: email, password: password);
    if (operation != _operation) return;
    await _adopt(profile);
  }

  /// Creates the account, which the API signs straight in.
  ///
  /// The new account has no name yet, so the router sends it to onboarding. The
  /// controller does not care; deciding where a profile leads is the router's job
  /// and duplicating that rule here would give two places to get it wrong.
  Future<void> register({
    required String email,
    required String password,
  }) async {
    final operation = ++_operation;
    final profile = await _repository.register(
      email: email,
      password: password,
    );
    if (operation != _operation) return;
    await _adopt(profile);
  }

  /// Updates the profile and adopts the stored record the API returns.
  Future<void> updateProfile({
    String? fullName,
    String? universityId,
    String? facultyId,
    int? yearOfStudy,
    bool? academicDataConsented,
    List<String>? primaryCourseUnitIds,
  }) async {
    final operation = ++_operation;
    final profile = await _repository.updateProfile(
      fullName: fullName,
      universityId: universityId,
      facultyId: facultyId,
      yearOfStudy: yearOfStudy,
      academicDataConsented: academicDataConsented,
      primaryCourseUnitIds: primaryCourseUnitIds,
    );
    if (operation != _operation) return;
    await _adopt(profile);
  }

  /// Ends the session and returns to the signed-out state.
  Future<void> signOut() async {
    ++_operation;
    await _repository.signOut();
    await _cache?.clear();
    _cache?.deactivateAccount();
    _session.signedOut();
  }

  /// Tries the cold-start check again after it failed.
  ///
  /// Offered by the splash screen and by pull-to-refresh while offline. Without
  /// it a student whose connection dropped on launch has no way forward but
  /// force-quitting the app, which on a low-memory handset is not something they
  /// will think to do.
  ///
  /// A failure while a cached session is already showing does not send the app
  /// back to splash: the account is still usable, and the offline notice is the
  /// honest answer to whether the data is current.
  Future<void> retryRestore() => _restore(++_operation);

  /// Renews the access token for the HTTP client, ending the session if the
  /// server has refused it.
  ///
  /// This is where a warm app learns its credential is dead. The interceptor
  /// only knows a refresh failed; the repository has already cleared the token
  /// when the refusal came from the server, and left it alone when the failure
  /// was the network. "No token left" is therefore the same fact as "that
  /// account is over", and acting on it is what stops a running app sitting on
  /// screens whose every request answers 401 until the student force-quits.
  ///
  /// Returns whether the session is still usable, which is exactly what the
  /// interceptor retries on.
  Future<bool> refreshSession() async {
    final renewed = await _repository.refreshSession();
    if (renewed) return true;
    if (await _repository.hasStoredSession()) return false;
    await _endExpiredSession();
    return false;
  }

  /// Starts the cold-start check of the stored session.
  ///
  /// Called once, by [authControllerProvider] when it is first read, rather than
  /// exposed for the shell to remember to invoke -- a check nobody calls is a
  /// check that never happens, and an app held on splash forever.
  void startRestore() => unawaited(_startRestore(++_operation));

  Future<void> _startRestore(int operation) async {
    // The saved profile is shown before the network is asked, because the
    // network can take ten seconds to admit it is unreachable. A returning
    // student sees their own account and their saved rail immediately; the
    // restore below either confirms it or corrects it. A device with no stored
    // token is never let in on the snapshot alone.
    final cached = await _readCachedProfile();
    if (operation != _operation) return;
    if (cached != null && await _repository.hasStoredSession()) {
      if (operation != _operation) return;
      await _adopt(cached, isOffline: true, remember: false);
    }
    await _restore(operation);
  }

  Future<void> _restore(int operation) async {
    try {
      final profile = await _repository.restoreSession();
      if (operation != _operation) return;
      if (profile == null) {
        await _forgetAccount();
        _session.signedOut();
      } else {
        await _adopt(profile);
      }
    } on NetworkFailure catch (failure) {
      if (operation != _operation) return;
      final cached = await _readCachedProfile();
      if (operation != _operation) return;
      if (cached != null) {
        await _adopt(cached, isOffline: true, remember: false);
        return;
      }
      _session.stillUnknown(restoreFailure: failure);
    } on Failure {
      if (operation != _operation) return;
      // Anything else means the stored session is not usable, which is the
      // definition of signed out.
      await _forgetAccount();
      _session.signedOut();
    }
  }

  /// Drops the account the server has already refused.
  ///
  /// Deliberately not [signOut]: there is nothing left to revoke, and a goodbye
  /// request carrying a credential the API has just rejected is noise. What has
  /// to go is the local record of the account and every cached answer under it,
  /// so the next cold start cannot restore a session the server has ended.
  Future<void> _endExpiredSession() async {
    ++_operation;
    await _forgetAccount();
    _session.signedOut();
  }

  /// Adopts a profile and points the cache at the account it belongs to.
  ///
  /// The cache namespace is switched before the session is recorded, because the
  /// session change is what rebuilds every account-scoped provider. A provider
  /// rebuilt while the cache still pointed at the previous account would read
  /// that account's saved answer, which is the leak this ordering prevents.
  Future<void> _adopt(
    UserProfile profile, {
    bool isOffline = false,
    bool remember = true,
  }) async {
    _cache?.activateAccount(profile.publicId);
    // Saved before the session changes, so the namespace and the snapshot agree
    // by the time any provider rebuilds. It is also what keeps a sign-out that
    // follows immediately from racing a still-pending write.
    if (remember) await _remember(profile);
    _session.signedIn(profile, isOffline: isOffline);
  }

  Future<void> _remember(UserProfile profile) async {
    try {
      await _cache?.writeProfile(profile.toJson());
    } on Object {
      // The snapshot is an enhancement. A cache that cannot be written must not
      // undo a sign-in the server has already accepted.
    }
  }

  Future<UserProfile?> _readCachedProfile() async {
    final cache = _cache;
    if (cache == null) return null;
    try {
      final json = await cache.readProfile();
      return json == null ? null : UserProfile.fromJson(json);
    } on Object {
      // A corrupt snapshot is the same as no snapshot.
      return null;
    }
  }

  /// Drops the saved account and every answer scoped to it.
  Future<void> _forgetAccount() async {
    try {
      await _cache?.clear();
    } on Object {
      // Deactivating below still stops a stale namespace being read.
    }
    _cache?.deactivateAccount();
  }
}

/// The universities the wizard offers.
final universitiesProvider = FutureProvider<List<UniversityOption>>((
  ref,
) async {
  try {
    final universities = await ref.read(authRepositoryProvider).universities();
    return universities.isEmpty ? const [mustFallbackUniversity] : universities;
  } on Object {
    return const [mustFallbackUniversity];
  }
});

/// The faculties the wizard offers.
// ignore: specify_nonobvious_property_types
final facultiesProvider = FutureProvider.family<List<Subject>, String>((
  ref,
  universityId,
) async {
  if (isMustFallbackUniversity(universityId)) {
    return mustFallbackFaculties;
  }
  try {
    final faculties = await ref
        .read(authRepositoryProvider)
        .faculties(universityId: universityId);
    if (faculties.isNotEmpty) return faculties;

    final universities = await ref.read(universitiesProvider.future);
    for (final university in universities) {
      if (university.publicId == universityId &&
          university.name == mustFallbackUniversityName) {
        return mustFallbackFaculties;
      }
    }
    return faculties;
  } on Failure {
    rethrow;
  }
});

typedef CourseUnitScope = ({String universityId, String? subjectId});

/// Course units scoped to the selected university and, when known, faculty.
// Riverpod infers the family provider type from the generic parameters, and the
// analyzer does not surface that type in a way it can prove without the
// explicit ignore.
// ignore: specify_nonobvious_property_types
final courseUnitsProvider =
    FutureProvider.family<List<CourseUnitOption>, CourseUnitScope>((
      ref,
      scope,
    ) {
      if (scope.universityId.isEmpty) return Future.value(const []);
      return ref
          .read(authRepositoryProvider)
          .courseUnits(
            universityId: scope.universityId,
            subjectId: scope.subjectId,
          );
    });

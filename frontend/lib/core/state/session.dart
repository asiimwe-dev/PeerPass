import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';

/// Whether the app knows who is signed in.
enum SessionStatus {
  /// Stored tokens have not been checked yet. The router holds here rather than
  /// showing sign-in, so a returning student is not flashed the sign-in screen
  /// before landing on their home screen.
  unknown,

  authenticated,

  unauthenticated,
}

/// Who is signed in, as far as the app is concerned.
///
/// Lives in `core/` rather than in the auth feature, and that placement is the
/// point. "Who is signed in" is not a property of authentication -- it is a fact
/// about the running app that the router, the home screen, and the auth screens
/// all need, and AGENTS.md forbids one feature reading another's presentation
/// layer. Holding it here means there is one answer, one place to look, and no
/// second copy that can drift from the first.
@immutable
class SessionState {
  const SessionState({required this.status, this.profile, this.restoreFailure});

  /// The app has not yet established whether anyone is signed in.
  ///
  /// [restoreFailure] is set only when the attempt failed for a reason the
  /// student can do something about -- a dropped connection, a server that was
  /// down. It is null while the attempt is still in flight.
  const SessionState.unknown({this.restoreFailure})
    : status = SessionStatus.unknown,
      profile = null;

  const SessionState.signedOut()
    : status = SessionStatus.unauthenticated,
      profile = null,
      restoreFailure = null;

  const SessionState.signedIn(UserProfile this.profile)
    : status = SessionStatus.authenticated,
      restoreFailure = null;

  final SessionStatus status;

  /// The signed-in user's own record.
  ///
  /// Null unless signed in. [UserProfile.needsOnboarding] answers whether the
  /// wizard still has to run, so no second "incomplete" flag is computed here.
  final UserProfile? profile;

  /// Why the cold-start attempt failed, when it did.
  ///
  /// Carried on the state rather than thrown, because the one screen that can do
  /// something about it is the splash screen the router is already holding on. A
  /// thrown error here would have nowhere to go and would surface as a blank
  /// screen.
  final Failure? restoreFailure;

  bool get isSignedIn => status == SessionStatus.authenticated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          other.status == status &&
          other.profile == profile &&
          other.restoreFailure == restoreFailure;

  @override
  int get hashCode => Object.hash(status, profile, restoreFailure);

  @override
  String toString() => 'SessionState($status)';
}

/// The session, as app-level state.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Records who is signed in.
///
/// Every method is a pure state transition with no I/O. That is deliberate: this
/// class is in `core/`, which must not import from `features/`, so it cannot call
/// the repository. The feature that does have the repository -- auth -- performs
/// the call and reports the outcome here. Splitting "do the network thing" from
/// "record the result" is what lets core own the answer without owning the work.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState.unknown();

  /// Records a successful sign-in, sign-up, or profile update.
  ///
  /// The whole stored record is adopted rather than merged into a local copy.
  /// The server is the authority on what was stored -- in particular on the
  /// consent timestamp, which it sets once and will not move -- so a client that
  /// patched its own copy would eventually disagree with it.
  void signedIn(UserProfile profile) => state = SessionState.signedIn(profile);

  /// Records that nobody is signed in.
  void signedOut() => state = const SessionState.signedOut();

  /// Records that the session is still unknown, optionally because a check failed.
  ///
  /// A failed check is not a sign-out. A device on a bad connection still holds a
  /// valid session, and signing a student out because their train went into a
  /// tunnel would lose their place. The status stays unknown so the router keeps
  /// holding on splash, and the failure rides along so splash can say what
  /// happened and offer a retry.
  void stillUnknown({Failure? restoreFailure}) =>
      state = SessionState.unknown(restoreFailure: restoreFailure);
}

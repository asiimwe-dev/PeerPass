import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';

/// A student who has finished onboarding. Any signed-in state is this shape, so
/// the tests below are about the session, not about the person.
const UserProfile _student = UserProfile(
  publicId: 'user-1',
  email: 'achieng@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
);

/// A fresh container per test, so one test's session cannot leak into the next.
ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SessionState defaults', () {
    test('starts unknown, with no profile and no failure', () {
      // Cold start. The router holds on splash in this state rather than showing
      // sign-in, so a returning student is not flashed the wrong screen.
      const state = SessionState.unknown();

      expect(state.status, SessionStatus.unknown);
      expect(state.profile, isNull);
      expect(state.restoreFailure, isNull);
      expect(state.isSignedIn, isFalse);
    });

    test('is signed out with no profile and no failure', () {
      const state = SessionState.signedOut();

      expect(state.status, SessionStatus.unauthenticated);
      expect(state.profile, isNull);
      expect(state.restoreFailure, isNull);
      expect(state.isSignedIn, isFalse);
    });
  });

  group('SessionController', () {
    test('the first read is unknown, with no profile and no failure', () {
      // Nothing has checked the stored token yet. A non-null failure here would
      // mean the splash screen told the student something that never happened.
      final state = _container().read(sessionControllerProvider);

      expect(state.status, SessionStatus.unknown);
      expect(state.profile, isNull);
      expect(state.restoreFailure, isNull);
    });

    test('signedIn records the profile the API returned', () {
      // The server is the authority on what was stored, so the whole record is
      // adopted rather than merged into a local copy that could drift.
      final container = _container();
      container.read(sessionControllerProvider.notifier).signedIn(_student);

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.authenticated);
      expect(state.profile, _student);
      expect(state.isSignedIn, isTrue);
    });

    test('signedOut clears the profile', () {
      final container = _container();
      container.read(sessionControllerProvider.notifier).signedIn(_student);
      container.read(sessionControllerProvider.notifier).signedOut();

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.unauthenticated);
      expect(state.profile, isNull);
    });

    test('stillUnknown leaves the status unknown and the failure null', () {
      // A restore that has not come back yet, and did not fail: the splash
      // screen is holding with nothing to report and nothing to offer.
      final container = _container();
      container
          .read(sessionControllerProvider.notifier)
          .stillUnknown();

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.unknown);
      expect(state.restoreFailure, isNull);
      expect(state.profile, isNull);
    });

    test('stillUnknown with a failure keeps the status unknown', () {
      // A failed cold-start check is not a sign-out. A student whose train went
      // into a tunnel still holds a valid session, and the router must keep
      // holding on splash rather than sending them to sign-in and losing the
      // session they had.
      final container = _container();
      container
          .read(sessionControllerProvider.notifier)
          .stillUnknown(restoreFailure: const NetworkFailure());

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.unknown);
      expect(state.profile, isNull);
      expect(state.restoreFailure, isA<NetworkFailure>());
      expect(state.isSignedIn, isFalse);
    });
  });

  group('SessionState equality', () {
    test('two signed-in states for the same profile are equal', () {
      expect(const SessionState.signedIn(_student), const SessionState.signedIn(_student));
      expect(
        const SessionState.signedIn(_student).hashCode,
        const SessionState.signedIn(_student).hashCode,
      );
    });

    test('a state with a failure is not equal to one without', () {
      // Riverpod compares states to decide whether listeners rebuild. A compare
      // that ignored the failure would leave splash showing "still working" over
      // an error the student is entitled to read.
      expect(
        const SessionState.unknown(restoreFailure: NetworkFailure()),
        isNot(const SessionState.unknown()),
      );
    });

    test('a signed-in state is not equal to an unknown one', () {
      expect(const SessionState.signedIn(_student), isNot(const SessionState.unknown()));
      expect(
        const SessionState.signedIn(_student),
        isNot(const SessionState.signedOut()),
      );
    });
  });
}

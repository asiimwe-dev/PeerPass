import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/notifications/data/repositories/fake_notifications_repository.dart';
import 'package:peerpass/features/notifications/data/repositories/notifications_repository.dart';
import 'package:peerpass/features/notifications/presentation/providers/notification_providers.dart';

const UserProfile _first = UserProfile(
  publicId: 'student-1',
  email: 'first@must.ac.ug',
  fullName: 'First Student',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'faculty-1',
  yearOfStudy: 1,
);

const UserProfile _second = UserProfile(
  publicId: 'student-2',
  email: 'second@must.ac.ug',
  fullName: 'Second Student',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'faculty-1',
  yearOfStudy: 2,
);

void main() {
  test('signing in as another account forgets the previous inbox', () async {
    // The providers outlive a session, and a shared handset is normal in the
    // pilot. Before this, the second student to sign in was shown the first
    // student's notifications until the screen refreshed.
    final repository = FakeNotificationsRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        notificationsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    // The router owns the listener that watches the signed-in identity.
    container.read(routerProvider);
    // Let the cold-start restore settle on "signed out" before acting as a
    // student, so it cannot overwrite the identity this test sets up.
    await Future<void>.delayed(Duration.zero);

    container.read(sessionControllerProvider.notifier).signedIn(_first);
    await container.read(notificationInboxProvider.future);
    expect(repository.inboxOffsets, [0]);

    container.read(sessionControllerProvider.notifier).signedIn(_second);
    await container.read(notificationInboxProvider.future);

    // A second first-page read is the provider being rebuilt for the new
    // account, not the old state handed over unchanged.
    expect(repository.inboxOffsets, [0, 0]);
  });
}

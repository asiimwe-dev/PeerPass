import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';

const UserProfile _student = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student},
);

/// Hands [AuthController] the [Ref] it expects.
///
/// Normally the controller is built by its own provider, whose first read also
/// starts the cold-start restore. These tests are about the one call that
/// happens after that restore, so they take a ref and drive it directly rather
/// than racing a second restore against the refresh under test.
final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _container(FakeAuthRepository repository) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

AuthController _controller(ProviderContainer container) =>
    AuthController(container.read(_refProvider));

/// A repository whose token the server has just refused.
///
/// The real repository clears the stored pair on `AuthFailure` and leaves it
/// alone on a transport failure, so this mirrors the refusal case: the token is
/// gone by the time [refreshSession] answers false.
class _RefusedRefreshRepository extends FakeAuthRepository {
  _RefusedRefreshRepository({super.session, super.refreshToken});

  @override
  Future<bool> refreshSession() async {
    refreshToken = null;
    return false;
  }
}

/// A repository that could not reach the server at all.
class _UnreachableRefreshRepository extends FakeAuthRepository {
  _UnreachableRefreshRepository({super.session, super.refreshToken});

  @override
  Future<bool> refreshSession() async => false;
}

void main() {
  test('a refused refresh signs the account out', () async {
    final repository = _RefusedRefreshRepository(
      session: _student,
      refreshToken: 'refresh',
    );
    final container = _container(repository);
    container.read(sessionControllerProvider.notifier).signedIn(_student);

    final renewed = await _controller(container).refreshSession();

    expect(renewed, isFalse);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unauthenticated,
      reason: 'a dead credential must not leave the app on screens that 401',
    );
  });

  test('a refresh the network swallowed keeps the account', () async {
    // The student is on a train, not signed out. Clearing here would sign them
    // out of an account the server has never refused.
    final repository = _UnreachableRefreshRepository(
      session: _student,
      refreshToken: 'refresh',
    );
    final container = _container(repository);
    container.read(sessionControllerProvider.notifier).signedIn(_student);

    final renewed = await _controller(container).refreshSession();

    expect(renewed, isFalse);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(await repository.hasStoredSession(), isTrue);
  });

  test('a renewed token leaves the account where it was', () async {
    final repository = FakeAuthRepository(
      session: _student,
      refreshToken: 'refresh',
    );
    final container = _container(repository);
    container.read(sessionControllerProvider.notifier).signedIn(_student);

    expect(await _controller(container).refreshSession(), isTrue);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
  });
}

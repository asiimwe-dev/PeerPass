import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/models/subject.dart';
import 'package:peerpass/core/models/university_option.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/competencies/data/models/tutor_claim.dart';
import 'package:peerpass/features/competencies/data/repositories/competencies_repository.dart';
import 'package:peerpass/features/competencies/data/repositories/fake_competencies_repository.dart';
import 'package:peerpass/features/home/presentation/screens/profile_screen.dart';

const _profile = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: {UserRole.student},
  universityId: 'university-1',
  facultyId: 'faculty-computing',
);

const _computing = Subject(publicId: 'faculty-computing', name: 'Computing');
const _medicine = Subject(publicId: 'faculty-medicine', name: 'Medicine');

Future<ProviderContainer> _pumpProfile(
  WidgetTester tester,
  AuthRepository repository, {
  UserProfile? profile,
  CompetenciesRepository? competenciesRepository,
}) async {
  // Seed both. The container's controller is what the screen reads, and the
  // repository's own copy is what it merges an update into and returns -- a fake
  // with no session answers `updateProfile` with a null profile, which is a
  // harness gap rather than anything the screen could handle.
  final signedIn = profile ?? _profile;
  if (repository is FakeAuthRepository) repository.session = signedIn;
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      if (competenciesRepository != null)
        competenciesRepositoryProvider.overrideWithValue(
          competenciesRepository,
        ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier).signedIn(signedIn);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    ),
  );
  await tester.pump();
  return container;
}

FakeAuthRepository _repositoryWithFaculties() {
  return FakeAuthRepository(
    universityOptions: const [
      UniversityOption(publicId: 'university-1', name: 'MUST'),
    ],
    facultyOptions: const [_computing, _medicine],
  );
}

void main() {
  testWidgets('shows the university name rather than its identifier', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      universityOptions: const [
        UniversityOption(publicId: 'university-1', name: 'MUST'),
      ],
    );

    await _pumpProfile(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('MUST'), findsOneWidget);
    expect(find.text('university-1'), findsNothing);
  });

  testWidgets('does not expose the identifier when the catalogue fails', (
    tester,
  ) async {
    final repository = _UnavailableUniversityRepository();

    await _pumpProfile(tester, repository);
    await tester.pumpAndSettle();

    // The faculty row resolves from the same catalogue, so it is unavailable
    // too; what matters is that neither row leaks the raw identifier.
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('university-1'), findsNothing);
  });

  testWidgets('shows the faculty name rather than its identifier', (
    tester,
  ) async {
    await _pumpProfile(tester, _repositoryWithFaculties());
    await tester.pumpAndSettle();

    expect(find.text('Computing'), findsOneWidget);
    expect(find.text('faculty-computing'), findsNothing);
  });

  testWidgets('shows the faculty without offering to change it', (
    tester,
  ) async {
    // The faculty decides the whole academic scope -- catalogue, tutor rail,
    // modules, competencies -- so moving it is an operator action. A row that
    // looks tappable would promise a change the app does not make.
    final repository = _repositoryWithFaculties();

    await _pumpProfile(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Computing'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tap(find.text('Computing'));
    await tester.pumpAndSettle();

    expect(repository.profileUpdates, isEmpty);
    expect(find.text('Medicine'), findsNothing);
  });

  testWidgets('says when no faculty is recorded', (tester) async {
    // A record that predates the field, or one the catalogue no longer lists,
    // reads as missing rather than as a spinner that never resolves.
    await _pumpProfile(
      tester,
      _repositoryWithFaculties(),
      profile: const UserProfile(
        publicId: 'user-1',
        email: 'student@must.ac.ug',
        fullName: 'Achieng Okello',
        roles: {UserRole.student},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Faculty'),
        matching: find.text('Not provided'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the applications row is hidden before the first application', (
    tester,
  ) async {
    await _pumpProfile(tester, _repositoryWithFaculties());

    expect(find.text('Tutor applications'), findsNothing);
  });

  testWidgets('a submitted application opens its status screen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: AppRoutes.myApplications,
          builder: (_, _) => const Scaffold(body: Text('the list')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final repository = _repositoryWithFaculties()..session = _profile;
    final claims = FakeCompetenciesRepository(
      claims: [
        TutorClaim(
          id: 'claim-1',
          courseUnitId: 'unit-1',
          courseUnitCode: 'CSC2101',
          courseUnitName: 'Operating Systems',
          gradeId: 'grade-1',
          gradeLabel: 'A',
          statusWire: 'pending',
          status: TutorClaimStatus.pending,
          gradePoints: 5,
          meetsThreshold: true,
          createdAt: DateTime.utc(2026, 11),
          evidenceReference: 'Transcript',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        competenciesRepositoryProvider.overrideWithValue(claims),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionControllerProvider.notifier).signedIn(_profile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Tutor applications'));
    await tester.pumpAndSettle();

    expect(find.text('the list'), findsOneWidget);
  });
}

class _UnavailableUniversityRepository extends FakeAuthRepository {
  @override
  Future<List<UniversityOption>> universities() async {
    throw StateError('catalogue unavailable');
  }
}

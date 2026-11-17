import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/program_option.dart';
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

const _computerScience = ProgramOption(
  publicId: 'programme-cs',
  name: 'Computer Science',
  facultyId: 'faculty-computing',
);
const _informationTechnology = ProgramOption(
  publicId: 'programme-bit',
  name: 'Information Technology',
  facultyId: 'faculty-computing',
);

const _profileWithProgramme = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: {UserRole.student},
  universityId: 'university-1',
  facultyId: 'faculty-computing',
  programId: 'programme-cs',
  programName: 'Computer Science',
  primaryCourseUnitIds: ['unit-1'],
);

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

FakeAuthRepository _repositoryWithProgrammes() {
  return FakeAuthRepository(
    universityOptions: const [
      UniversityOption(publicId: 'university-1', name: 'MUST'),
    ],
    facultyOptions: const [_computing, _medicine],
    programOptions: const [_computerScience, _informationTechnology],
  );
}

/// A repository that refuses a programme change, the way the API rejects a shelf
/// outside the caller's faculty.
class _RefusingProgrammeRepository extends FakeAuthRepository {
  _RefusingProgrammeRepository()
    : super(
        universityOptions: const [
          UniversityOption(publicId: 'university-1', name: 'MUST'),
        ],
        facultyOptions: const [_computing, _medicine],
        programOptions: const [_computerScience, _informationTechnology],
      );

  @override
  Future<UserProfile> updateProfile({
    String? fullName,
    String? universityId,
    String? facultyId,
    String? programId,
    int? yearOfStudy,
    bool? academicDataConsented,
    List<String>? primaryCourseUnitIds,
  }) {
    if (programId != null) {
      throw const ValidationFailure('That programme is not in your faculty.');
    }
    return super.updateProfile(
      fullName: fullName,
      universityId: universityId,
      facultyId: facultyId,
      yearOfStudy: yearOfStudy,
      academicDataConsented: academicDataConsented,
      primaryCourseUnitIds: primaryCourseUnitIds,
    );
  }
}

/// A repository whose programme change prunes the declared units, as the API
/// does when the new shelf does not publish them.
class _PruningProgrammeRepository extends FakeAuthRepository {
  _PruningProgrammeRepository()
    : super(
        universityOptions: const [
          UniversityOption(publicId: 'university-1', name: 'MUST'),
        ],
        facultyOptions: const [_computing, _medicine],
        programOptions: const [_computerScience, _informationTechnology],
      );

  @override
  Future<UserProfile> updateProfile({
    String? fullName,
    String? universityId,
    String? facultyId,
    String? programId,
    int? yearOfStudy,
    bool? academicDataConsented,
    List<String>? primaryCourseUnitIds,
  }) async {
    final updated = await super.updateProfile(
      fullName: fullName,
      universityId: universityId,
      facultyId: facultyId,
      programId: programId,
      yearOfStudy: yearOfStudy,
      academicDataConsented: academicDataConsented,
      primaryCourseUnitIds: primaryCourseUnitIds,
    );
    return updated.copyWith(primaryCourseUnitIds: const []);
  }
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
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Faculty'),
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Faculty'),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );

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

  testWidgets('shows the programme name rather than its identifier', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      _repositoryWithProgrammes(),
      profile: _profileWithProgramme,
    );
    await tester.pumpAndSettle();

    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('programme-cs'), findsNothing);
  });

  testWidgets('a faculty with no programme says so and offers no control', (
    tester,
  ) async {
    // A faculty that publishes no programmes is a normal catalogue state. The
    // row explains the scope instead of opening a sheet with nothing in it.
    await _pumpProfile(tester, _repositoryWithFaculties());
    await tester.pumpAndSettle();

    final programmeRow = find.widgetWithText(ListTile, 'Programme');
    expect(
      find.descendant(of: programmeRow, matching: find.text('Whole faculty')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: programmeRow,
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('the programme row opens the catalogue and saves the choice', (
    tester,
  ) async {
    final repository = _repositoryWithProgrammes();
    final container = await _pumpProfile(
      tester,
      repository,
      profile: _profileWithProgramme,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Computer Science'));
    await tester.pumpAndSettle();

    // Both shelves of the faculty are offered, and the current one is marked.
    expect(find.text('Information Technology'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Information Technology'));
    await tester.pumpAndSettle();

    expect(repository.profileUpdates, hasLength(1));
    expect(repository.profileUpdates.single['program_id'], 'programme-bit');
    expect(
      container.read(sessionControllerProvider).profile?.programName,
      'Information Technology',
    );
    expect(find.text('Programme updated.'), findsOneWidget);
  });

  testWidgets('choosing the current programme sends nothing', (tester) async {
    final repository = _repositoryWithProgrammes();
    await _pumpProfile(
      tester,
      repository,
      profile: _profileWithProgramme,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Computer Science'));
    await tester.pumpAndSettle();

    // The row behind the sheet also says "Computer Science"; the last one is the
    // sheet entry that was tapped.
    await tester.tap(find.text('Computer Science').last);
    await tester.pumpAndSettle();

    expect(repository.profileUpdates, isEmpty);
  });

  testWidgets('a refused change keeps the row and says why', (tester) async {
    // The API checks the programme belongs to the caller's faculty. A refusal
    // has to leave the stored choice on screen rather than pretend it changed.
    final container = await _pumpProfile(
      tester,
      _RefusingProgrammeRepository(),
      profile: _profileWithProgramme,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Computer Science'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Information Technology'));
    await tester.pumpAndSettle();

    expect(find.text('That programme is not in your faculty.'), findsOneWidget);
    expect(
      container.read(sessionControllerProvider).profile?.programId,
      'programme-cs',
    );
    expect(find.text('Computer Science'), findsOneWidget);
  });

  testWidgets('says when the change removed course units', (tester) async {
    // The server prunes declared units the new shelf does not publish. Saying so
    // is what stops the removal reading as the app having lost their courses.
    final container = await _pumpProfile(
      tester,
      _PruningProgrammeRepository(),
      profile: _profileWithProgramme,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Computer Science'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Information Technology'));
    await tester.pumpAndSettle();

    expect(
      find.text('Programme updated. Course units outside it were removed.'),
      findsOneWidget,
    );
    expect(
      container.read(sessionControllerProvider).profile?.primaryCourseUnitIds,
      isEmpty,
    );
  });
}

class _UnavailableUniversityRepository extends FakeAuthRepository {
  @override
  Future<List<UniversityOption>> universities() async {
    throw StateError('catalogue unavailable');
  }
}

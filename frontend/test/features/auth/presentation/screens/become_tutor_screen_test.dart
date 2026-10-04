import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/subject.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/auth/data/datasources/remote_academics_datasource.dart';
import 'package:peerpass/features/auth/data/models/university_option.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/auth/presentation/screens/become_tutor_screen.dart';

const UserProfile _student = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'faculty-1',
  fullName: 'Amina Nansubuga',
);

const List<CourseUnitOption> _courseUnits = <CourseUnitOption>[
  CourseUnitOption(
    publicId: 'unit-1',
    code: 'BIT 221',
    name: 'Database Programming',
  ),
  CourseUnitOption(
    publicId: 'unit-2',
    code: 'BIT 311',
    name: 'Software Engineering',
  ),
];

const List<GradeOption> _gradeOptions = <GradeOption>[
  GradeOption(publicId: 'grade-1', label: 'B+', gradePoints: 4.5),
  // The grade scale stores exact decimal values, including the A benchmark.
  // ignore: prefer_int_literals
  GradeOption(publicId: 'grade-2', label: 'A', gradePoints: 5.0),
];

Future<void> _pumpScreen(WidgetTester tester, FakeAuthRepository repo) async {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier).signedIn(_student);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const BecomeTutorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ErrorGradeRepository implements AuthRepository {
  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<UserProfile> register({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<UserProfile?> restoreSession() async => _student;

  @override
  Future<bool> refreshSession() async => true;

  @override
  Future<List<UniversityOption>> universities() async => const [
    UniversityOption(
      publicId: 'university-1',
      name: 'Mbarara University of Science and Technology',
    ),
  ];

  @override
  Future<String?> universityNameById(String universityId) async => null;

  @override
  Future<List<Subject>> faculties({required String universityId}) async => const [];

  @override
  Future<List<CourseUnitOption>> courseUnits({
    String? universityId,
    String? subjectId,
  }) async => _courseUnits;

  @override
  Future<List<GradeOption>> grades({String? universityId}) async {
    throw const ServerFailure('The server sent something we could not read.');
  }

  @override
  Future<void> submitCompetency({
    required String courseUnitId,
    required String gradeId,
    required String source,
    String? evidenceReference,
    String? notes,
  }) async {}

  @override
  Future<UserProfile> updateProfile({
    String? fullName,
    String? universityId,
    String? facultyId,
    int? yearOfStudy,
    bool? academicDataConsented,
    List<String>? primaryCourseUnitIds,
  }) async => _student;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

void main() {
  testWidgets(
    'shows the MUST grade options when the live grade catalogue is empty',
    (tester) async {
      final repository = FakeAuthRepository(
        session: _student,
        refreshToken: 'refresh',
        universityOptions: const [
          UniversityOption(
            publicId: 'university-1',
            name: 'Mbarara University of Science and Technology',
          ),
        ],
        courseUnitOptions: _courseUnits,
      );

      await _pumpScreen(tester, repository);

      await tester.tap(find.byKey(const ValueKey('Grade')));
      await tester.pumpAndSettle();

      expect(find.text('B+ (4.5)').last, findsOneWidget);
      expect(
        find.text(
          'Showing the saved MUST grading scale while we refresh the catalogue.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows a retry state instead of the MUST fallback when the grade fetch errors',
    (tester) async {
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(_ErrorGradeRepository())],
      );
      addTearDown(container.dispose);
      container.read(sessionControllerProvider.notifier).signedIn(_student);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BecomeTutorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('We could not load the published grading scale right now.'),
        findsOneWidget,
      );
      expect(find.text('Retry grades'), findsOneWidget);
      expect(
        find.text('Showing the saved MUST grading scale while we refresh the catalogue.'),
        findsNothing,
      );
    },
  );

  testWidgets('a student can submit tutor proof for one unit', (tester) async {
    final repository = FakeAuthRepository(
      session: _student,
      refreshToken: 'refresh',
      courseUnitOptions: _courseUnits,
      gradeOptions: _gradeOptions,
    );

    await _pumpScreen(tester, repository);

    await tester.tap(find.byKey(const ValueKey('Course unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BIT 221 · Database Programming').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('Grade')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B+ (4.5)').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Evidence reference or link'),
      'https://drive.example/transcript.pdf',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes for the reviewer'),
      'I completed this in my final year.',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Submit proof'));
    await tester.tap(find.text('Submit proof'));
    await tester.pumpAndSettle();

    expect(repository.submittedCompetencies, isNotEmpty);
    expect(repository.submittedCompetencies.first['source'], 'transcript');
    expect(repository.submittedCompetencies.first['course_unit_id'], 'unit-1');
    expect(repository.submittedCompetencies.first['grade_id'], 'grade-1');
  });

  testWidgets('requires an explicit grade selection', (tester) async {
    final repository = FakeAuthRepository(
      session: _student,
      refreshToken: 'refresh',
      courseUnitOptions: _courseUnits,
      gradeOptions: _gradeOptions,
    );

    await _pumpScreen(tester, repository);

    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit proof'),
    );
    expect(submit.onPressed, isNull);
    expect(repository.submittedCompetencies, isEmpty);

    await tester.tap(find.byKey(const ValueKey('Grade')));
    await tester.pumpAndSettle();
    expect(find.text('Select grade').last, findsOneWidget);
  });
}

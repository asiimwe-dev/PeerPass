import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/fake_auth_repository.dart';
import 'package:peerpass/features/matching/data/repositories/fake_matching_repository.dart';
import 'package:peerpass/features/matching/data/repositories/matching_repository.dart';
import 'package:peerpass/features/matching/presentation/widgets/ask_composer.dart';

const UserProfile _student = UserProfile(
  publicId: 'user-1',
  email: 'student@must.ac.ug',
  fullName: 'Achieng Okello',
  roles: <UserRole>{UserRole.student},
  universityId: 'university-1',
  facultyId: 'subject-1',
  yearOfStudy: 2,
);

const List<CourseUnit> _units = [
  CourseUnit(publicId: 'unit-mat', code: 'MAT 221', name: 'Linear Algebra'),
  CourseUnit(
    publicId: 'unit-csc',
    code: 'CSC 202',
    name: 'Database Programming',
  ),
];

/// A router whose results screen echoes what it was given, so a test can assert
/// the path and the question the composer produced rather than that a screen
/// merely opened.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const Scaffold(body: SingleChildScrollView(child: AskComposer())),
      ),
      GoRoute(
        path: AppRoutes.matching,
        builder: (_, _) => const Scaffold(body: Text('Course catalogue here')),
      ),
      GoRoute(
        path: '${AppRoutes.matching}/:unitId',
        builder: (_, state) => Scaffold(
          body: Text(
            'results ${state.pathParameters['unitId']} '
            '${state.uri.queryParameters['topic'] ?? '(no topic)'}',
          ),
        ),
      ),
    ],
  );
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  List<CourseUnit> units = _units,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(session: _student, refreshToken: 'refresh'),
      ),
      matchingRepositoryProvider.overrideWithValue(
        FakeMatchingRepository(courseUnits: units),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier).signedIn(_student);

  final router = _router();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  return router;
}

void main() {
  testWidgets('offers the catalogue as chips and preselects the first unit', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('MAT 221'), findsOneWidget);
    expect(find.text('CSC 202'), findsOneWidget);
    // The selected unit's full name, so a student who only recognises the code
    // is not asked to remember it.
    expect(find.text('Linear Algebra'), findsOneWidget);
    // The catalogue is never a dead end, even when every unit fits.
    expect(find.text('View more'), findsOneWidget);
  });

  testWidgets('View more lists the whole catalogue and keeps the question', (
    tester,
  ) async {
    final units = List<CourseUnit>.generate(
      6,
      (index) => CourseUnit(
        publicId: 'unit-$index',
        code: 'CSC 50$index',
        name: 'Course unit $index',
      ),
    );
    final router = await _pump(tester, units: units);

    await tester.enterText(find.byType(TextField), 'indexing');
    await tester.tap(find.text('View more'));
    await tester.pumpAndSettle();

    expect(find.text('All course units'), findsOneWidget);
    // The fourth unit is behind the three visible chips, and the sheet is how a
    // student reaches it without losing the question they already typed.
    expect(find.text('CSC 503'), findsOneWidget);

    await tester.tap(find.text('CSC 503'));
    await tester.pumpAndSettle();

    expect(find.text('All course units'), findsNothing);
    expect(find.text('Course unit 3'), findsOneWidget);

    await tester.tap(find.text('Find me a tutor'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/matching/unit-3?topic=indexing');
  });

  testWidgets('sends the preselected unit and the question in the route', (
    tester,
  ) async {
    final router = await _pump(tester);

    await tester.enterText(find.byType(TextField), 'eigenvalues before Friday');
    await tester.tap(find.text('Find me a tutor'));
    await tester.pumpAndSettle();

    expect(
      router.state.uri.toString(),
      '/matching/unit-mat?topic=eigenvalues+before+Friday',
    );
    expect(
      find.text('results unit-mat eigenvalues before Friday'),
      findsOneWidget,
    );
  });

  testWidgets('a tapped chip changes the unit that is asked about', (
    tester,
  ) async {
    final router = await _pump(tester);

    await tester.tap(find.text('CSC 202'));
    await tester.pump();

    expect(find.text('Database Programming'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'normalisation');
    await tester.tap(find.text('Find me a tutor'));
    await tester.pumpAndSettle();

    expect(
      router.state.uri.toString(),
      '/matching/unit-csc?topic=normalisation',
    );
  });

  testWidgets('with no catalogue, the action opens the picker', (tester) async {
    await _pump(tester, units: const []);

    expect(
      find.text(
        'Your faculty has not published course units yet. You can still browse '
        'and ask.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Find me a tutor'));
    await tester.pumpAndSettle();

    expect(find.text('Course catalogue here'), findsOneWidget);
  });
}

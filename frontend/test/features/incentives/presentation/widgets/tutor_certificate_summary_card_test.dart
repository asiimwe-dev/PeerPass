import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/data/repositories/fake_incentives_repository.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';
import 'package:peerpass/features/incentives/presentation/widgets/tutor_certificate_summary_card.dart';

GoRouter _router() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: TutorCertificateSummaryCard()),
        ),
      ),
      GoRoute(
        path: AppRoutes.certificate,
        builder: (_, _) => const Scaffold(body: Text('Certificate screen')),
      ),
      GoRoute(
        path: AppRoutes.tutorVerification,
        builder: (_, _) =>
            const Scaffold(body: Text('Tutor verification screen')),
      ),
    ],
  );
}

Widget _app(IncentivesRepository repository, GoRouter router) {
  final container = ProviderContainer(
    overrides: [incentivesRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

/// Pumps long enough for the provider's future to land, without settling an
/// animation the card does not own.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

Future<void> _pump(WidgetTester tester, IncentivesRepository repository) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(_app(repository, router));
  await _flush(tester);
}

void main() {
  testWidgets('shows the hours and the fraction the API reported', (
    tester,
  ) async {
    await _pump(tester, FakeIncentivesRepository(certifiedMinutes: 600));

    expect(find.text('Certificate progress'), findsOneWidget);
    expect(find.text('10h of 40h'), findsOneWidget);
    expect(find.text('30h to go'), findsOneWidget);
    expect(find.text('View certificate'), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 0.0001));
  });

  testWidgets('does not call it earned on hours alone', (tester) async {
    // The compact dashboard card has to carry the same three-condition verdict
    // as the full screen; a summary that rounded forty hours in four sittings
    // into "earned" would be the bug in a smaller font.
    await _pump(
      tester,
      FakeIncentivesRepository(certifiedMinutes: 2400, completedSessions: 4),
    );

    expect(find.text('Certificate earned'), findsNothing);
    expect(find.text('6 more sessions to go'), findsOneWidget);
  });

  testWidgets('View certificate opens the certificate screen', (tester) async {
    await _pump(tester, FakeIncentivesRepository(certifiedMinutes: 600));

    await tester.tap(find.text('View certificate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Certificate screen'), findsOneWidget);
  });

  testWidgets(
    'a caller with no tutor profile is offered the way to become one',
    (tester) async {
      await _pump(tester, FakeIncentivesRepository(hasTutorProfile: false));

      expect(find.text('Certificate progress'), findsOneWidget);
      expect(
        find.textContaining('once your tutor application is approved'),
        findsOneWidget,
      );
      expect(find.text('Apply to teach'), findsOneWidget);
      expect(find.text('View certificate'), findsNothing);
      // Not a bar at zero: that would say they are failing a requirement they have
      // not yet been given a way to meet.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('Apply to teach opens the verification screen', (tester) async {
    await _pump(tester, FakeIncentivesRepository(hasTutorProfile: false));

    await tester.tap(find.text('Apply to teach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tutor verification screen'), findsOneWidget);
  });

  testWidgets('says so while the answer is still on its way', (tester) async {
    final repository = _PendingIncentivesRepository();
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router));
    await tester.pump();

    expect(find.text('Checking your certificate progress'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await repository.answer(FakeIncentivesRepository(certifiedMinutes: 600));
    await _flush(tester);

    expect(find.text('10h of 40h'), findsOneWidget);
  });

  testWidgets('a failed fetch shows a message and a retry', (tester) async {
    await _pump(
      tester,
      FakeIncentivesRepository(failure: const NetworkFailure()),
    );

    expect(
      find.text('No connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text('View certificate'), findsNothing);
  });

  testWidgets('the retry button asks the API again', (tester) async {
    final repository = _FlakyIncentivesRepository(
      recovered: FakeIncentivesRepository(certifiedMinutes: 900),
    );

    await _pump(tester, repository);

    expect(repository.calls, 1);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await _flush(tester);

    expect(repository.calls, 2);
    expect(find.text('15h of 40h'), findsOneWidget);
  });
}

/// A repository that holds the fetch open until the test releases it.
class _PendingIncentivesRepository implements IncentivesRepository {
  final Completer<CertificateEligibility> _completer =
      Completer<CertificateEligibility>();

  Future<void> answer(IncentivesRepository repository) async {
    _completer.complete(await repository.myCertificate());
  }

  @override
  Future<CertificateEligibility> myCertificate() => _completer.future;
}

/// A repository whose first fetch fails and whose second answers.
class _FlakyIncentivesRepository implements IncentivesRepository {
  _FlakyIncentivesRepository({required this.recovered});

  final IncentivesRepository recovered;
  int _attempts = 0;

  int get calls => _attempts;

  @override
  Future<CertificateEligibility> myCertificate() {
    _attempts++;
    if (_attempts == 1) throw const NetworkFailure();
    return recovered.myCertificate();
  }
}

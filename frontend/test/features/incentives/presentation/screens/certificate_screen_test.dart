import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/theme/app_theme.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/data/repositories/fake_incentives_repository.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';
import 'package:peerpass/features/incentives/presentation/screens/certificate_screen.dart';
import 'package:peerpass/features/incentives/presentation/widgets/certificate_progress_card.dart';

/// A container with [repository] behind the incentives provider.
///
/// Only the incentives provider is overridden. The screen reads nothing about the
/// signed-in account -- which is the point of a self-scoped endpoint -- so a test
/// that had to stand up a session first would be testing something the screen
/// does not do.
ProviderContainer _container(IncentivesRepository repository) {
  final container = ProviderContainer(
    overrides: [incentivesRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const CertificateScreen()),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the hours banked against the hours a certificate needs', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _container(FakeIncentivesRepository(certifiedMinutes: 600)),
    );

    expect(find.text('My certificate'), findsOneWidget);
    expect(find.text('10h of 40h'), findsOneWidget);
    expect(find.text('30h to go'), findsOneWidget);
  });

  testWidgets('the bar is drawn at the fraction the API reported', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _container(FakeIncentivesRepository(certifiedMinutes: 1200)),
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.5, 0.0001));
  });

  testWidgets('a minute short reads as a minute short, not as earned', (
    tester,
  ) async {
    // The rounding that would matter is 2399 minutes displayed as 40 of 40. If a
    // future change rounds, this screen would tell a tutor they have something
    // they do not.
    await _pumpScreen(
      tester,
      _container(FakeIncentivesRepository(certifiedMinutes: 2399)),
    );

    expect(find.text('39h 59m of 40h'), findsOneWidget);
    expect(find.text('Certificate earned'), findsNothing);
    expect(find.text('1 minute to go'), findsOneWidget);
  });

  testWidgets('says earned and drops the remaining count once earned', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _container(
        FakeIncentivesRepository(certifiedMinutes: 2400),
      ),
    );

    expect(find.text('Certificate earned'), findsOneWidget);
    expect(find.text('Earned'), findsOneWidget);
    // A remaining count under "earned" would be the screen arguing with itself.
    expect(find.textContaining('to go'), findsNothing);
  });

  testWidgets('reads the threshold off the wire rather than assuming one', (
    tester,
  ) async {
    // A pilot that lowers the bar to 600 must not need a client change. This is
    // the client-side half of the promise the backend makes about Settings: if
    // anything here were hardcoded, a tutor would be told they need 40h when the
    // operator needs 10.
    await _pumpScreen(
      tester,
      _container(
        FakeIncentivesRepository(certifiedMinutes: 300, requiredMinutes: 600),
      ),
    );

    expect(find.text('5h of 10h'), findsOneWidget);
    expect(find.text('5h to go'), findsOneWidget);
    expect(find.text('Certificate earned'), findsNothing);
  });

  testWidgets('is earned on the minute at a lowered threshold', (tester) async {
    await _pumpScreen(
      tester,
      _container(
        FakeIncentivesRepository(certifiedMinutes: 600, requiredMinutes: 600),
      ),
    );

    expect(find.text('Certificate earned'), findsOneWidget);
    expect(find.textContaining('to go'), findsNothing);
  });

  testWidgets('a caller with no tutor profile is offered the way to become one', (
    tester,
  ) async {
    // Not a bar at zero, and not an error: they are not a tutor yet, which is a
    // state with a next step.
    await _pumpScreen(
      tester,
      _container(
        FakeIncentivesRepository(hasTutorProfile: false),
      ),
    );

    expect(find.text('You are not a tutor yet'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Apply to teach'), findsOneWidget);
  });

  testWidgets('says so while the answer is still on its way', (tester) async {
    // A repository that will not answer until the test says so, because a fake
    // that returns immediately never produces a loading state to assert on.
    final repository = _PendingIncentivesRepository();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(repository),
        child: MaterialApp(theme: AppTheme.light, home: const CertificateScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Checking your progress'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await repository.answer(FakeIncentivesRepository(certifiedMinutes: 600));
    await _settle(tester);

    expect(find.text('10h of 40h'), findsOneWidget);
  });

  testWidgets('shows a failure a tutor can act on, and no raw error text', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _container(
        FakeIncentivesRepository(failure: const NetworkFailure()),
      ),
    );

    expect(find.byType(CertificateProgressCard), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('the retry button asks the API again', (tester) async {
    final repository = _FlakyIncentivesRepository(
      recovered: FakeIncentivesRepository(certifiedMinutes: 900),
    );
    final container = _container(repository);

    await _pumpScreen(tester, container);
    expect(repository.calls, 1);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await _settle(tester);

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

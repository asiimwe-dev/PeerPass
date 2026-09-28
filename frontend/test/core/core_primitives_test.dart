import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/grading_scale.dart';
import 'package:peerpass/core/models/university.dart';
import 'package:peerpass/core/storage/token_store.dart';

void main() {
  group('Failure defaults', () {
    test('each failure type carries a message safe to show a user', () {
      const failures = <Failure>[
        NetworkFailure(),
        AuthFailure(),
        ValidationFailure('Invalid'),
        NotFoundFailure(),
        ConflictFailure(),
        ServerFailure(),
        CancelledFailure(),
        UnknownFailure(),
      ];

      for (final failure in failures) {
        expect(failure.message, isNotEmpty, reason: '$failure');
      }
    });

    test('a validation failure defaults to no field errors', () {
      const failure = ValidationFailure('Invalid');

      expect(failure.fieldErrors, isEmpty);
    });
  });

  group('ValidationFailure equality', () {
    test('ignores field order', () {
      const first = ValidationFailure(
        'Invalid',
        fieldErrors: {'email': 'Bad', 'name': 'Missing'},
      );
      const second = ValidationFailure(
        'Invalid',
        fieldErrors: {'name': 'Missing', 'email': 'Bad'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('differs when a field error changes', () {
      const first = ValidationFailure('Invalid', fieldErrors: {'a': '1'});
      const second = ValidationFailure('Invalid', fieldErrors: {'a': '2'});

      expect(first, isNot(second));
    });
  });

  group('InMemoryTokenStore', () {
    test('starts with no session', () async {
      final store = InMemoryTokenStore();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('round-trips a written session', () async {
      final store = InMemoryTokenStore();

      await store.write(accessToken: 'access', refreshToken: 'refresh');

      expect(await store.readAccessToken(), 'access');
      expect(await store.readRefreshToken(), 'refresh');
    });

    test('clears both tokens, as a rejected refresh requires', () async {
      final store = InMemoryTokenStore(accessToken: 'a', refreshToken: 'b');

      await store.clear();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('University', () {
    test('carries the grading scale its competency rule is evaluated on', () {
      const university = University(
        publicId: 'uni-1',
        name: 'Makerere University',
        gradingScale: GradingScale(
          publicId: 'scale-1',
          name: '5.0 scale',
          maxPoints: 5,
        ),
      );

      expect(university.gradingScale.maxPoints, 5);
    });

    test('compares by value', () {
      const first = University(
        publicId: 'uni-1',
        name: 'Makerere University',
        gradingScale: GradingScale(
          publicId: 'scale-1',
          name: '5.0 scale',
          maxPoints: 5,
        ),
      );
      const second = University(
        publicId: 'uni-1',
        name: 'Makerere University',
        gradingScale: GradingScale(
          publicId: 'scale-1',
          name: '5.0 scale',
          maxPoints: 5,
        ),
      );

      expect(first, second);
    });
  });
}

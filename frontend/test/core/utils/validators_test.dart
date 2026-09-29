import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/utils/validators.dart';

void main() {
  group('Validators.required', () {
    test('rejects null, empty, and whitespace-only input', () {
      expect(Validators.required(null), isNotNull);
      expect(Validators.required(''), isNotNull);
      expect(Validators.required('   '), isNotNull);
    });

    test('accepts a value with content', () {
      expect(Validators.required('Calculus'), isNull);
    });
  });

  group('Validators.length', () {
    test('rejects a value below the minimum', () {
      expect(Validators.length('ab', min: 3, max: null), isNotNull);
    });

    test('rejects a value above the maximum', () {
      expect(Validators.length('abcdef', min: 1, max: 3), isNotNull);
    });

    test('measures length after trimming, so padding cannot pass', () {
      expect(Validators.length('  ab  ', min: 3, max: null), isNotNull);
    });

    test('accepts a value within bounds', () {
      expect(Validators.length('abc', min: 3, max: 5), isNull);
    });
  });

  group('Validators.email', () {
    test('accepts ordinary addresses', () {
      expect(Validators.email('student@ug.ac.ug'), isNull);
      expect(Validators.email('first.last@uni.ac.ug'), isNull);
    });

    test('rejects an address with no domain or no local part', () {
      expect(Validators.email('student@'), isNotNull);
      expect(Validators.email('@ug.ac.ug'), isNotNull);
      expect(Validators.email('student@ug'), isNotNull);
    });

    test('rejects empty input with a specific message', () {
      expect(Validators.email(''), 'Email address is required');
    });
  });

  group('Validators.ugandanPhoneNumber', () {
    test('accepts local, bare, and international forms', () {
      expect(Validators.ugandanPhoneNumber('0772123456'), isNull);
      expect(Validators.ugandanPhoneNumber('+256772123456'), isNull);
      expect(Validators.ugandanPhoneNumber('256772123456'), isNull);
    });

    test('ignores spaces and dashes a student may type', () {
      expect(Validators.ugandanPhoneNumber('0772 123 456'), isNull);
      expect(Validators.ugandanPhoneNumber('0772-123-456'), isNull);
    });

    test('rejects a foreign number rather than guessing its country', () {
      expect(Validators.ugandanPhoneNumber('+14155552671'), isNotNull);
    });

    test('rejects a number of the wrong length', () {
      expect(Validators.ugandanPhoneNumber('077212345'), isNotNull);
      expect(Validators.ugandanPhoneNumber('07721234567'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('requires at least twelve characters, the API minimum', () {
      // Pinned on the boundary rather than around it. A test that only checked
      // a very short value would still pass if the minimum were dropped to four,
      // and the value it used to accept would be a password the API refuses.
      expect(Validators.password('a' * 11), isNotNull);
      expect(Validators.password('a' * 12), isNull);
    });

    test('rejects an empty password', () {
      expect(Validators.password(''), isNotNull);
    });

    test('rejects a password of only whitespace', () {
      expect(Validators.password(' ' * 12), isNotNull);
    });
  });

  group('Validators.passwordsMatch', () {
    test('requires the confirmation to be present', () {
      expect(Validators.passwordsMatch('longenough12', ''), isNotNull);
      expect(Validators.passwordsMatch('longenough12', null), isNotNull);
    });

    test('rejects a mismatched confirmation', () {
      expect(
        Validators.passwordsMatch('longenough12', 'longenough13'),
        isNotNull,
      );
    });

    test('accepts a matching confirmation', () {
      expect(Validators.passwordsMatch('longenough12', 'longenough12'), isNull);
    });
  });

  group('Validators.rating', () {
    test('accepts the one-to-five range the API allows', () {
      for (var value = 1; value <= 5; value++) {
        expect(Validators.rating(value), isNull, reason: 'rating $value');
      }
    });

    test('rejects a rating outside that range', () {
      expect(Validators.rating(0), isNotNull);
      expect(Validators.rating(6), isNotNull);
    });

    test('rejects a missing rating', () {
      expect(Validators.rating(null), 'Select a rating');
    });
  });
}

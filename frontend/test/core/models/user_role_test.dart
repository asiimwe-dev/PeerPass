import 'package:flutter_test/flutter_test.dart';
import 'package:ulearn/core/models/user_role.dart';

void main() {
  group('UserRole.fromWire', () {
    test('parses every declared role', () {
      for (final role in UserRole.values) {
        expect(UserRole.fromWire(role.wireValue), role);
      }
    });

    test('returns null for a role this client does not know', () {
      expect(UserRole.fromWire('administrator'), isNull);
    });

    test('returns null for null or a wrong-case value', () {
      expect(UserRole.fromWire(null), isNull);
      expect(UserRole.fromWire('Student'), isNull);
    });
  });

  test('wire values are snake case, as the API documents', () {
    expect(
      UserRole.values.map((role) => role.wireValue),
      everyElement(matches(RegExp(r'^[a-z_]+$'))),
    );
  });
}

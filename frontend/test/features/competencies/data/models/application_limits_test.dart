import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/competencies/data/models/application_limits.dart';

void main() {
  group('reading application limits', () {
    test('reads the live count and the cap', () {
      final limits = ApplicationLimits.fromJson(const {
        'active_count': 2,
        'max_active_course_units': 3,
      });

      expect(limits.activeCount, 2);
      expect(limits.maxActiveCourseUnits, 3);
      expect(limits.atCap, isFalse);
      expect(limits.remainingSlots, 1);
    });

    test('is at the cap when the count reaches the limit', () {
      final limits = ApplicationLimits.fromJson(const {
        'active_count': 3,
        'max_active_course_units': 3,
      });

      expect(limits.atCap, isTrue);
      expect(limits.remainingSlots, 0);
    });

    test('never reports negative room', () {
      // The server enforces the cap, so a count above it should not happen. If
      // it does, the screen must still be able to render without offering a
      // negative number of applications.
      final limits = ApplicationLimits.fromJson(const {
        'active_count': 4,
        'max_active_course_units': 3,
      });

      expect(limits.remainingSlots, 0);
    });

    test('a missing count is a body the client cannot read', () {
      expect(
        () => ApplicationLimits.fromJson(const {'max_active_course_units': 3}),
        throwsFormatException,
      );
    });

    test('a cap below one is refused rather than disabling every tutor', () {
      // Zero would read as "you may never apply", which is not a state the API
      // documents and not something a client should silently render.
      expect(
        () => ApplicationLimits.fromJson(const {
          'active_count': 0,
          'max_active_course_units': 0,
        }),
        throwsFormatException,
      );
    });

    test('a negative active count is refused', () {
      expect(
        () => ApplicationLimits.fromJson(const {
          'active_count': -1,
          'max_active_course_units': 3,
        }),
        throwsFormatException,
      );
    });
  });
}

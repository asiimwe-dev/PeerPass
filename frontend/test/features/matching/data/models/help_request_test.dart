import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/features/matching/data/models/help_request.dart';

/// The API's own response shape, one field at a time.
///
/// Written out rather than built by a helper so a field that stops being sent is
/// visible here instead of hidden behind a default in a fixture.
Map<String, dynamic> _response({
  String? id,
  String? status,
  String? matchedTutorId,
  String? description,
  String? createdAt,
}) {
  return {
    'id': id ?? 'request-1',
    'tutee_id': 'student-1',
    'course_unit_id': 'unit-1',
    'topic': 'eigenvalues',
    'description': description,
    'status': status ?? 'pending_confirmation',
    'matched_tutor_id': matchedTutorId,
    'created_at': createdAt ?? '2026-03-04T09:12:00Z',
  };
}

void main() {
  group('reading a help request', () {
    test('reads the whole documented response', () {
      final request = HelpRequest.fromJson(
        _response(
          matchedTutorId: 'tutor-1',
          description: 'Stuck on the second eigenvector.',
        ),
      );

      expect(request.id, 'request-1');
      expect(request.tuteeId, 'student-1');
      expect(request.courseUnitId, 'unit-1');
      expect(request.topic, 'eigenvalues');
      expect(request.description, 'Stuck on the second eigenvector.');
      expect(request.status, HelpRequestStatus.pendingConfirmation);
      expect(request.statusWire, 'pending_confirmation');
      expect(request.matchedTutorId, 'tutor-1');
      expect(request.createdAt, DateTime.utc(2026, 3, 4, 9, 12));
    });

    test('a request nobody was chosen for has no tutor, and that is fine', () {
      // Not a malformed response: `matched_tutor_id` is absent on every `open`
      // request, and refusing the whole response over it would hide a request the
      // student just made.
      final request = HelpRequest.fromJson(_response(status: 'open'));

      expect(request.matchedTutorId, isNull);
      expect(request.status, HelpRequestStatus.open);
      expect(request.statusSentence, contains('choose a tutor'));
    });

    test('an absent description reads as none rather than as text', () {
      final request = HelpRequest.fromJson(_response());

      expect(request.description, isNull);
    });

    test('an id that is not a string is read as no tutor', () {
      // Under-claims rather than inventing. A tutor id the client cannot read is
      // not a tutor it can name, and showing one would put a button on the row
      // for a person the API never named.
      final request = HelpRequest.fromJson(
        _response(matchedTutorId: '')..['matched_tutor_id'] = 42,
      );

      expect(request.matchedTutorId, isNull);
    });

    test('a code from a newer server is kept, and not guessed at', () {
      final request = HelpRequest.fromJson(
        _response(status: 'awaiting_pilot_funding'),
      );

      // The wire spelling survives so a bug report can quote it, and the parsed
      // status is null rather than a state this build has never heard of. Falling
      // back to something recognised would show a request in a state it is not in.
      expect(request.statusWire, 'awaiting_pilot_funding');
      expect(request.status, isNull);
      expect(request.isAwaitingTutor, isFalse);
      expect(request.isDeclined, isFalse);
    });

    test('every status the API documents is one this client can read', () {
      // The two lists are the same rule written twice, and this is what notices
      // when the API gains one and this build does not.
      const wireStatuses = [
        'open',
        'pending_confirmation',
        'matched',
        'declined',
        'withdrawn',
        'expired',
      ];

      expect(
        HelpRequestStatus.values.map((status) => status.wireValue),
        wireStatuses,
      );
    });

    test('a response without a topic is unreadable, and says so', () {
      final json = _response()..remove('topic');

      expect(() => HelpRequest.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('a response without a status is unreadable, and says so', () {
      // A request whose status cannot be read must not reach a screen: every
      // decision in this flow is a function of it.
      final json = _response()..remove('status');

      expect(() => HelpRequest.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('a response without an id is unreadable, and says so', () {
      final json = _response()..remove('id');

      expect(() => HelpRequest.fromJson(json), throwsA(isA<FormatException>()));
    });
  });

  group('what a screen reads off a status', () {
    test('a chosen tutor and no answer yet is the waiting state', () {
      final request = HelpRequest.fromJson(
        _response(status: 'pending_confirmation', matchedTutorId: 'tutor-1'),
      );

      expect(request.isAwaitingTutor, isTrue);
      expect(request.isDeclined, isFalse);
    });

    test('a refusal is a refusal, and the tutor is kept', () {
      // The named tutor is retained because a student cannot reconstruct *who*
      // turned them down from a status word alone.
      final request = HelpRequest.fromJson(
        _response(status: 'declined', matchedTutorId: 'tutor-1'),
      );

      expect(request.isDeclined, isTrue);
      expect(request.isAwaitingTutor, isFalse);
      expect(request.matchedTutorId, 'tutor-1');
      expect(request.statusSentence, contains('turned this request down'));
    });

    test('being confirmed is not being awaited', () {
      final request = HelpRequest.fromJson(_response(status: 'matched'));

      expect(request.isAwaitingTutor, isFalse);
      expect(request.isDeclined, isFalse);
    });

    test('every status has a sentence a student can read', () {
      // A status with no copy would render as a bare word from the API, which is
      // the outcome this file exists to avoid.
      for (final status in HelpRequestStatus.values) {
        final request = HelpRequest.fromJson(
          _response(status: status.wireValue),
        );
        expect(request.statusSentence, isNotEmpty, reason: status.wireValue);
      }
    });

    test('only the states a tutor could still act on are live', () {
      expect(HelpRequestStatus.open.isLive, isTrue);
      expect(HelpRequestStatus.pendingConfirmation.isLive, isTrue);
      for (final status in [
        HelpRequestStatus.matched,
        HelpRequestStatus.declined,
        HelpRequestStatus.withdrawn,
        HelpRequestStatus.expired,
      ]) {
        expect(status.isLive, isFalse, reason: status.wireValue);
      }
    });
  });

  test('two readings of the same response are the same request', () {
    expect(
      HelpRequest.fromJson(_response(matchedTutorId: 'tutor-1')),
      HelpRequest.fromJson(_response(matchedTutorId: 'tutor-1')),
    );
    expect(
      HelpRequest.fromJson(_response(matchedTutorId: 'tutor-1')),
      isNot(HelpRequest.fromJson(_response(matchedTutorId: 'tutor-2'))),
    );
  });
}

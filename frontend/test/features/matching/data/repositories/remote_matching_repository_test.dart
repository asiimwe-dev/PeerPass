import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/matching/data/datasources/remote_matching_datasource.dart';
import 'package:peerpass/features/matching/data/repositories/remote_matching_repository.dart';

/// A recorded request, so a test can assert on what the client actually sent.
class _Call {
  _Call(this.method, this.path, this.query, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;

  @override
  String toString() => '$method $path?$query $body';
}

/// Answers requests from a script, and records what it was asked.
///
/// Copied in shape from the sessions repository test: the thing under test is the
/// wire -- which route, which body, which query -- and a mock at the datasource
/// boundary would let a renamed field pass.
class _FakeServer implements HttpClientAdapter {
  final List<_Call> calls = [];
  final List<Object?> _replies = [];

  void reply(int status, Object? body) => _replies.add(_Reply(status, body));

  void fail(DioException error) => _replies.add(error);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(
      _Call(
        options.method,
        options.path,
        options.queryParameters.map(
          (key, value) => MapEntry(key, value as Object),
        ),
        _decode(options.data),
      ),
    );

    final reply = _replies.removeAt(0);
    if (reply is DioException) throw reply;

    final r = reply! as _Reply;
    return ResponseBody.fromString(
      r.body == null ? '' : jsonEncode(r.body),
      r.status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Object? _decode(Object? data) {
  if (data is! String) return data;
  try {
    return jsonDecode(data);
  } on FormatException {
    return data;
  }
}

class _Reply {
  _Reply(this.status, this.body);

  final int status;
  final Object? body;
}

Map<String, dynamic> _matchResponse({
  List<Map<String, dynamic>> candidates = const [],
  List<Map<String, dynamic>> exclusions = const [],
  bool? widened,
  bool? none,
}) {
  return {
    'course_unit_id': 'unit-1',
    'request_id': null,
    'generated_at': '2026-03-04T09:12:00Z',
    'widened': ?widened,
    'no_eligible_tutors': ?none,
    'candidates': candidates,
    'exclusions': exclusions,
  };
}

Map<String, dynamic> _tutor({String id = 'tutor-1'}) {
  return {
    'user_id': id,
    'full_name': 'Grace Okello',
    'standing': 'verified',
    'average_rating': '4.10',
    'completed_sessions': 12,
  };
}

Map<String, dynamic> _candidate({String id = 'tutor-1'}) {
  return {
    'tutor': _tutor(id: id),
    'course_unit_id': 'unit-1',
    'competency_grade_points': '82.50',
    'meets_threshold': true,
    'score': 0.93,
  };
}

/// The API's own refusal, as `MatchRequest` validation produces it.
Map<String, dynamic> _problem({
  int status = 422,
  String title = 'Validation failed',
  String detail = 'course_unit_id is required.',
  Map<String, String>? errors,
}) {
  return {
    'type': 'https://peerpass.app/problems/validation',
    'title': title,
    'status': status,
    'detail': detail,
    'errors': ?errors,
  };
}

void main() {
  late _FakeServer server;
  late RemoteMatchingRepository repository;

  setUp(() {
    server = _FakeServer();
    // validateStatus matches the production client, so a 4xx throws here exactly
    // as it would against the real API. A test client that returned error statuses
    // as values would never exercise the failure mapping.
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.peerpass.test',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    )..httpClientAdapter = server;
    repository = RemoteMatchingRepository(RemoteMatchingDatasource(dio));
  });

  group('asking who may take a course unit', () {
    test('posts the three documented fields, and nothing else', () async {
      server.reply(
        200,
        _matchResponse(candidates: [_candidate()]),
      );

      await repository.suggestions(courseUnitId: 'unit-1');

      // `MatchRequest` forbids unknown keys, so this is also the test that would
      // fail loudly if a client grew a field the API rejects with a 422. The unit
      // route is the one this client calls: `/help-requests/{id}/matches` answers
      // about a request the caller owns, which this client does not send.
      final call = server.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/v1/matching/suggestions');
      expect(call.body, {
        'course_unit_id': 'unit-1',
        'widen_to_subject': false,
      });
    });

    test('does not widen unless the caller asked', () async {
      server.reply(200, _matchResponse());

      await repository.suggestions(courseUnitId: 'unit-1');

      final body = server.calls.single.body! as Map<String, dynamic>;
      // Off by default, because the API's default is off and widening by
      // default would return tutors who cannot help with the course asked about.
      expect(body['widen_to_subject'], isFalse);
    });

    test('sends the widening flag the caller set', () async {
      server.reply(200, _matchResponse(widened: true, none: true));

      final result = await repository.suggestions(
        courseUnitId: 'unit-1',
        widenToSubject: true,
      );

      final body = server.calls.single.body! as Map<String, dynamic>;
      expect(body['widen_to_subject'], isTrue);
      // And the flag in the response is what the caller is told about: this is the
      // field a screen has to render, not the one it asked with.
      expect(result.widened, isTrue);
    });

    test('leaves limit out rather than inventing a rail length', () async {
      server.reply(200, _matchResponse());

      await repository.suggestions(courseUnitId: 'unit-1');

      final body = server.calls.single.body! as Map<String, dynamic>;
      // The API's own bound stays the client's bound, so a server-side change
      // does not leave the app asking for a different number of tutors than it
      // used to.
      expect(body.containsKey('limit'), isFalse);
    });

    test('sends a limit the caller asked for', () async {
      server.reply(200, _matchResponse());

      await repository.suggestions(courseUnitId: 'unit-1', limit: 3);

      final body = server.calls.single.body! as Map<String, dynamic>;
      expect(body['limit'], 3);
    });

    test('nobody being eligible arrives as a result, not a failure', () async {
      server.reply(
        200,
        _matchResponse(
          widened: true,
          none: true,
          exclusions: [
            {'tutor_id': 'tutor-9', 'reason': 'below_threshold'},
          ],
        ),
      );

      final result = await repository.suggestions(
        courseUnitId: 'unit-1',
        widenToSubject: true,
      );

      expect(result.noEligibleTutors, isTrue);
      expect(result.candidates, isEmpty);
      expect(result.exclusions.single.explanation, isNotEmpty);
    });

    test('the score is read and kept off the screen', () async {
      // Asserted in a repository test because this is where the wire shape is
      // known: `score` is a JSON number, unlike the Decimal fields beside it.
      server.reply(200, _matchResponse(candidates: [_candidate()]));

      final result = await repository.suggestions(courseUnitId: 'unit-1');

      expect(result.candidates.single.score, 0.93);
      expect(result.candidates.single.competencyGradePoints, 82.5);
    });

    test('a refused body is a ValidationFailure naming the field', () async {
      server.reply(
        422,
        _problem(
          errors: {'course_unit_id': 'Field required.'},
        ),
      );

      await expectLater(
        repository.suggestions(courseUnitId: 'unit-1'),
        throwsA(
          isA<ValidationFailure>().having(
            (failure) => failure.fieldErrors,
            'fieldErrors',
            containsPair('course_unit_id', 'Field required.'),
          ),
        ),
      );
    });

    test('a body of the wrong shape is a ServerFailure, not a crash', () async {
      // The parse runs inside the repository's guard, so an unreadable response
      // reaches a screen as a message instead of a `FormatException` type name.
      server.reply(200, {'candidates': 'not a list'});

      await expectLater(
        repository.suggestions(courseUnitId: 'unit-1'),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('the course unit catalogue', () {
    test('is read as the bare array the endpoint returns', () async {
      server.reply(200, [
        {'id': 'unit-1', 'code': 'MAT 221', 'name': 'Linear Algebra II'},
        {'id': 'unit-2', 'code': 'PHY 105', 'name': 'Mechanics'},
      ]);

      final units = await repository.courseUnits();

      expect(units.map((unit) => unit.code), ['MAT 221', 'PHY 105']);
      expect(units.first.publicId, 'unit-1');
      expect(units.first.name, 'Linear Algebra II');
      expect(server.calls.single.path, '/v1/academics/course-units');
      // No university of its own: the session's is the one that counts, and the
      // API already scopes the answer to the caller.
      expect(server.calls.single.query, isEmpty);
    });

    test('sends a university when the caller has one to name', () async {
      server.reply(200, const []);

      await repository.courseUnits(universityId: 'university-1');

      expect(
        server.calls.single.query,
        {'university_id': 'university-1'},
      );
    });

    test('an empty catalogue is a list, not a failure', () async {
      server.reply(200, const []);

      expect(await repository.courseUnits(), isEmpty);
    });

    test('a dropped connection is a NetworkFailure', () async {
      server.fail(
        DioException(
          requestOptions: RequestOptions(path: '/v1/academics/course-units'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        ),
      );

      await expectLater(
        repository.courseUnits(),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}

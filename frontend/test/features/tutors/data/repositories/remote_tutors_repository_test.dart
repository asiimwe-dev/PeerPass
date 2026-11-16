import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/tutors/data/datasources/remote_tutors_datasource.dart';
import 'package:peerpass/features/tutors/data/repositories/remote_tutors_repository.dart';

import '../../../../support/memory_session_cache.dart';

/// A recorded request, so a test can assert on what the client actually sent.
class _Call {
  _Call(this.method, this.path, this.query, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;

  @override
  String toString() => '$method $path?$query ($body)';
}

/// Answers requests from a script, and records what it was asked.
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
        options.data,
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

class _Reply {
  _Reply(this.status, this.body);

  final int status;
  final Object? body;
}

Map<String, dynamic> _tutor({
  String id = 'tutor-1',
  String rating = '4.10',
  int sessions = 12,
}) {
  return {
    'user_id': id,
    'full_name': 'Grace Okello',
    'standing': 'verified',
    'average_rating': rating,
    'completed_sessions': sessions,
    'endorsed_course_unit_ids': ['unit-1'],
    'endorsement_count': 1,
  };
}

Map<String, dynamic> _detail({
  String id = 'tutor-1',
  int count = 1,
  List<String> ids = const ['unit-1'],
}) {
  return {
    'profile': {
      'user_id': id,
      'full_name': 'Grace Okello',
      'standing': 'verified',
      'average_rating': '4.10',
      'completed_sessions': 12,
    },
    'endorsed_course_unit_ids': ids,
    'endorsement_count': count,
  };
}

Map<String, dynamic> _hq({bool accepting = true}) {
  return {
    'has_tutor_profile': true,
    'standing': 'probationary',
    'completed_sessions': 14,
    'average_rating': '4.80',
    'rating_count': 2,
    'certified_minutes': 600,
    'certificate_required_minutes': 2400,
    'certificate_remaining_minutes': 1800,
    'certificate_eligible': false,
    'certificate_progress': 0.25,
    'accepting_requests': accepting,
    'promotion': {
      'verified': false,
      'rated_sessions': 1,
      'sessions_required': 3,
      'sessions_remaining': 2,
      'minimum_average': '4.10',
      'meets_average': true,
      'progress': 0.3333333333333333,
    },
  };
}

/// The API's own refusal, as RFC 9457 problem details.
Map<String, dynamic> _problem({
  int status = 404,
  String title = 'Not found',
  String detail = 'Tutor not found.',
}) {
  return {
    'type': 'https://peerpass.app/problems/not-found',
    'title': title,
    'status': status,
    'detail': detail,
  };
}

void main() {
  late _FakeServer server;
  late RemoteTutorsRepository repository;

  setUp(() {
    server = _FakeServer();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.peerpass.test',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    )..httpClientAdapter = server;
    repository = RemoteTutorsRepository(RemoteTutorsDatasource(dio));
  });

  group('the top-tutors rail', () {
    test('asks for the array the API returns, with no limit sent', () async {
      server.reply(200, [_tutor()]);

      await repository.topTutors();

      final call = server.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/v1/tutors/top');
      expect(call.query, isEmpty);
    });

    test('narrows the rail to a course unit when one is given', () async {
      server.reply(200, [_tutor()]);

      await repository.topTutors(courseUnitId: 'unit-1');

      expect(server.calls.single.query, {'course_unit_id': 'unit-1'});
    });

    test('an empty rail is a list, not a failure', () async {
      server.reply(200, const []);

      expect(await repository.topTutors(), isEmpty);
    });

    test('a malformed rail entry becomes a ServerFailure', () async {
      // The repository guards the parse, so a body with no endorsement_count does
      // not throw a `FormatException` to the screen.
      server.reply(200, [
        {
          'user_id': 'tutor-1',
          'full_name': 'Grace',
          'standing': 'verified',
          'completed_sessions': 0,
        },
      ]);

      await expectLater(repository.topTutors(), throwsA(isA<ServerFailure>()));
    });

    test('a dropped connection is a NetworkFailure', () async {
      server.fail(
        DioException(
          requestOptions: RequestOptions(path: '/v1/tutors/top'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        ),
      );

      await expectLater(repository.topTutors(), throwsA(isA<NetworkFailure>()));
    });

    test('a saved rail stands in for a connection that never opened', () async {
      // Home must not be empty just because the API cannot be reached. The rail
      // is marked so the screen can say it is the saved copy rather than
      // presenting it as live.
      final cache = MemorySessionCache()..activateAccount('account-1');
      await cache.writeTopTutors([_tutor()]);
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.peerpass.test',
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      )..httpClientAdapter = server;
      final offlineRepository = RemoteTutorsRepository(
        RemoteTutorsDatasource(dio, cache: cache),
      );

      server.fail(
        DioException(
          requestOptions: RequestOptions(path: '/v1/tutors/top'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        ),
      );

      final rail = await offlineRepository.topTutors();

      expect(rail.single.tutor.fullName, 'Grace Okello');
      expect(rail.single.isOfflineCached, isTrue);
    });
  });

  group('the tutor HQ', () {
    test('reads the self-scoped endpoint and parses the summary', () async {
      server.reply(200, _hq());

      final hq = await repository.myHq();

      final call = server.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/v1/tutors/me');
      expect(call.query, isEmpty);
      expect(hq.hasTutorProfile, isTrue);
      expect(hq.averageRating, 4.8);
      expect(hq.promotion.sessionsRemaining, 2);
      expect(hq.acceptingRequests, isTrue);
    });

    test('saves availability with the body the API documents', () async {
      server.reply(200, _hq(accepting: false));

      final hq = await repository.setAcceptingRequests(false);

      final call = server.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, '/v1/tutors/me');
      expect(call.body, {'accepting_requests': false});
      // The API returns the whole summary, so the saved flag is read from the
      // response rather than patched into a stale local copy.
      expect(hq.acceptingRequests, isFalse);
    });

    test('a malformed summary becomes a ServerFailure', () async {
      server.reply(200, {'has_tutor_profile': true});

      await expectLater(repository.myHq(), throwsA(isA<ServerFailure>()));
    });

    test('a dropped connection is a NetworkFailure', () async {
      server.fail(
        DioException(
          requestOptions: RequestOptions(path: '/v1/tutors/me'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        ),
      );

      await expectLater(repository.myHq(), throwsA(isA<NetworkFailure>()));
    });

    test('a rejected availability save is translated too', () async {
      server.reply(403, _problem(status: 403, detail: 'Not a tutor.'));

      await expectLater(
        repository.setAcceptingRequests(false),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('one tutor', () {
    test('fetches by the path parameter the API documents', () async {
      server.reply(200, _detail());

      await repository.tutor('tutor-1');

      final call = server.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/v1/tutors/tutor-1');
      expect(call.query, isEmpty);
    });

    test('a missing tutor is a NotFoundFailure', () async {
      server.reply(404, _problem());

      await expectLater(
        repository.tutor('nope'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a malformed detail becomes a ServerFailure', () async {
      server.reply(200, {'profile': null, 'endorsement_count': 0});

      await expectLater(
        repository.tutor('tutor-1'),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('reviews', () {
    test('asks for the tutor own review path and parses the list', () async {
      server.reply(200, [
        {
          'id': 'review-1',
          'score': 5,
          'rater_initials': 'AO',
          'tags': ['patient'],
          'created_at': '2026-03-04T11:00:00Z',
        },
      ]);

      final reviews = await repository.reviews('tutor-1');

      final call = server.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/v1/tutors/tutor-1/reviews');
      // No limit sent means the API's own page size; the client does not pick
      // one on the caller's behalf when the caller did not ask.
      expect(call.query, isEmpty);
      expect(reviews.single.score, 5);
      expect(reviews.single.raterInitials, 'AO');
    });

    test('passes the page size straight through when one is given', () async {
      server.reply(200, const []);

      await repository.reviews('tutor-1', limit: 3);

      expect(server.calls.single.query, {'limit': 3});
    });

    test('no reviews is an empty list, not a failure', () async {
      // A new tutor is a normal state, and the profile says so plainly rather
      // than looking like the request broke.
      server.reply(200, const []);

      expect(await repository.reviews('tutor-1'), isEmpty);
    });

    test('a non-tutor is a NotFoundFailure, as the profile is', () async {
      server.reply(404, _problem());

      await expectLater(
        repository.reviews('student-1'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a malformed review becomes a ServerFailure', () async {
      server.reply(200, [
        {'id': 'review-1', 'score': 5},
      ]);

      await expectLater(
        repository.reviews('tutor-1'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a dropped connection is a NetworkFailure', () async {
      server.fail(
        DioException(
          requestOptions: RequestOptions(path: '/v1/tutors/tutor-1/reviews'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        ),
      );

      await expectLater(
        repository.reviews('tutor-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('course units for endorsed names', () {
    test('is read from the same catalogue endpoint', () async {
      server.reply(200, [
        {'id': 'unit-1', 'code': 'MAT 221', 'name': 'Linear Algebra II'},
      ]);

      final units = await repository.courseUnits();

      expect(units.single.code, 'MAT 221');
      expect(server.calls.single.path, '/v1/academics/course-units');
    });

    test('passes a university id when given', () async {
      server.reply(200, const []);

      await repository.courseUnits(universityId: 'university-1');

      expect(server.calls.single.query, {'university_id': 'university-1'});
    });
  });
}

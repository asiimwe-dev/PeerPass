import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/incentives/data/datasources/remote_incentives_datasource.dart';
import 'package:peerpass/features/incentives/data/repositories/remote_incentives_repository.dart';

/// A recorded request, so a test can assert on what the client actually sent.
class _Call {
  _Call(this.method, this.path);

  final String method;
  final String path;

  @override
  String toString() => '$method $path';
}

/// Answers requests from a script, and records what it was asked.
///
/// The same shape as the sessions and tutors repository tests: what is under test
/// here is the wire -- which path, which method, and what happens to each kind of
/// bad answer -- and a mock at the datasource boundary would let a renamed route
/// pass.
class _FakeServer implements HttpClientAdapter {
  final List<_Call> calls = [];
  final List<Object?> _replies = [];

  void reply(int status, Object? body) => _replies.add(_Reply(status, body));

  /// Sends text verbatim, so a test can answer with something that is not JSON at
  /// all -- a proxy's error page, or a gateway that gives up in plain text.
  void replyRaw(int status, String text) => _replies.add(_Raw(status, text));

  void fail(DioException error) => _replies.add(error);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(_Call(options.method, options.path));

    final reply = _replies.removeAt(0);
    if (reply is DioException) throw reply;

    if (reply is _Raw) {
      return ResponseBody.fromString(
        reply.text,
        reply.status,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }

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

class _Raw {
  _Raw(this.status, this.text);

  final int status;
  final String text;
}

Map<String, dynamic> _certificate({
  bool hasTutorProfile = true,
  bool eligible = false,
  int certifiedMinutes = 240,
  int requiredMinutes = 2400,
}) {
  return {
    'has_tutor_profile': hasTutorProfile,
    'eligible': eligible,
    'certified_minutes': certifiedMinutes,
    'required_minutes': requiredMinutes,
    'remaining_minutes': requiredMinutes - certifiedMinutes,
    'progress': certifiedMinutes / requiredMinutes,
    'generated_at': '2026-03-04T11:00:00Z',
  };
}

/// The API's own refusal, in the problem details shape it uses everywhere.
Map<String, dynamic> _problem({
  int status = 401,
  String title = 'Unauthorized',
  String detail = 'Not authenticated.',
}) {
  return {
    'type': 'https://peerpass.app/problems/authentication',
    'title': title,
    'status': status,
    'detail': detail,
  };
}

void main() {
  late _FakeServer server;
  late RemoteIncentivesRepository repository;

  setUp(() {
    server = _FakeServer();
    // `validateStatus` matches the production client, so a 4xx throws here exactly
    // as it would against the real API. A test client that returned error statuses
    // as values would never exercise the failure mapping.
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.peerpass.test',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    )..httpClientAdapter = server;

    repository = RemoteIncentivesRepository(RemoteIncentivesDatasource(dio));
  });

  test("asks for the caller's own certificate, with nothing identifying it", () async {
    // No user id in the path and no query: these are the caller's own hours, so a
    // test that saw a parameter here would be seeing a client that could be asked
    // about somebody else.
    server.reply(200, _certificate());

    await repository.myCertificate();

    expect(server.calls.single.method, 'GET');
    expect(server.calls.single.path, '/v1/incentives/certificate');
  });

  test("returns the API's answer, threshold included", () async {
    server.reply(
      200,
      _certificate(certifiedMinutes: 600, requiredMinutes: 600),
    );

    final eligibility = await repository.myCertificate();

    expect(eligibility.hasTutorProfile, isTrue);
    expect(eligibility.certifiedMinutes, 600);
    expect(eligibility.requiredMinutes, 600);
    expect(eligibility.remainingMinutes, 0);
  });

  test('returns a caller with no tutor profile, rather than failing', () async {
    server.reply(200, _certificate(hasTutorProfile: false, certifiedMinutes: 0));

    final eligibility = await repository.myCertificate();

    expect(eligibility.hasTutorProfile, isFalse);
    expect(eligibility.eligible, isFalse);
  });

  test('an expired session surfaces as an auth failure, not a number', () async {
    server.reply(401, _problem());

    await expectLater(repository.myCertificate(), throwsA(isA<AuthFailure>()));
  });

  test("a server fault keeps the API's own wording", () async {
    server.reply(500, _problem(status: 500, detail: 'Upstream is unavailable.'));

    await expectLater(
      repository.myCertificate(),
      throwsA(
        isA<ServerFailure>().having(
          (failure) => failure.message,
          'message',
          'Upstream is unavailable.',
        ),
      ),
    );
  });

  test('being offline surfaces as a network failure', () async {
    server.fail(
      DioException(
        requestOptions: RequestOptions(path: '/v1/incentives/certificate'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      repository.myCertificate(),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('a body that is not the documented shape is reported, not rethrown raw', () async {
    // The contract changed, or something in front of the API rewrote it. Either
    // way the tutor gets a message and a retry button, not a `FormatException`
    // arriving at the screen as an unknown error with a Dart type on it.
    server.reply(200, {'unexpected': true});

    await expectLater(
      repository.myCertificate(),
      throwsA(
        isA<ServerFailure>().having(
          (failure) => failure.message,
          'message',
          contains('could not read'),
        ),
      ),
    );
  });

  test(
    'a body that is not JSON at all never reaches the screen as raw text',
    () async {
    server.replyRaw(200, '<html>gateway timeout</html>');

    await expectLater(
      repository.myCertificate(),
      throwsA(
        isA<Failure>().having(
          (failure) => failure.message,
          'message',
          allOf(isNotEmpty, isNot(contains('<'))),
        ),
      ),
    );
  });
}

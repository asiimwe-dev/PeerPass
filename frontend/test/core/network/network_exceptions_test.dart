import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulearn/core/error/failures.dart';
import 'package:ulearn/core/network/network_exceptions.dart';

/// Builds a 401-shaped problem details response.
Response<dynamic> problemResponse(int status, Object? body) {
  final options = RequestOptions(path: '/test');
  return Response<dynamic>(
    requestOptions: options,
    statusCode: status,
    data: body,
  );
}

void main() {
  group('mapDioException on transport errors', () {
    test('maps a connection timeout to a retryable network failure', () {
      final failure = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(failure, isA<NetworkFailure>());
    });

    test('maps a dropped connection to a network failure', () {
      final failure = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
          error: const SocketException('failed'),
        ),
      );

      expect(failure, isA<NetworkFailure>());
    });

    test('maps a cancellation to its own failure, not an error', () {
      final failure = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.cancel,
        ),
      );

      expect(failure, isA<CancelledFailure>());
    });

    test('maps an unrecognised socket error to a network failure', () {
      final failure = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          // `unknown` is Dio's default type, which is exactly the case under
          // test here: the cause is only visible in `error`.
          error: const SocketException('unreachable'),
        ),
      );

      expect(failure, isA<NetworkFailure>());
    });

    test('maps an unparseable response to a server failure', () {
      final failure = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          error: const FormatException('bad json'),
        ),
      );

      expect(failure, isA<ServerFailure>());
    });
  });

  group('mapDioException on problem details responses', () {
    test('maps 400 to a validation failure', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 400,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(400, const {'detail': 'Bad input'}),
        ),
      );

      expect(failure, isA<ValidationFailure>());
    });

    test('surfaces per-field errors so a form can show them inline', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 422,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(422, const {
            'detail': 'Some fields are invalid',
            'errors': {'email': 'Enter a valid email address'},
          }),
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect((failure as ValidationFailure).fieldErrors, {
        'email': 'Enter a valid email address',
      });
    });

    test('maps 401 and 403 to an auth failure', () {
      for (final status in [401, 403]) {
        final failure = mapDioException(
          DioException.badResponse(
            statusCode: status,
            requestOptions: RequestOptions(path: '/test'),
            response: problemResponse(status, const {'detail': 'Nope'}),
          ),
        );

        expect(failure, isA<AuthFailure>(), reason: 'status $status');
      }
    });

    test('maps 404 to not found', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(404, const {'detail': 'No tutor'}),
        ),
      );

      expect(failure, isA<NotFoundFailure>());
    });

    test('maps 409 to a conflict', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 409,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(409, const {'detail': 'Already accepted'}),
        ),
      );

      expect(failure, isA<ConflictFailure>());
    });

    test('maps any 5xx to a server failure', () {
      for (final status in [500, 502, 503]) {
        final failure = mapDioException(
          DioException.badResponse(
            statusCode: status,
            requestOptions: RequestOptions(path: '/test'),
            response: problemResponse(status, const {'detail': 'Boom'}),
          ),
        );

        expect(failure, isA<ServerFailure>(), reason: 'status $status');
      }
    });

    test('maps an unexpected status to unknown, not server', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 418,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(418, const {'detail': 'Teapot'}),
        ),
      );

      expect(failure, isA<UnknownFailure>());
    });

    test('prefers the problem detail over the generic status message', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(404, const {'detail': 'Tutor was removed'}),
        ),
      );

      expect(failure.message, 'Tutor was removed');
    });

    test(
      'falls back to a safe message when the body is not problem details',
      () {
        final failure = mapDioException(
          DioException.badResponse(
            statusCode: 500,
            requestOptions: RequestOptions(path: '/test'),
            response: problemResponse(500, '<html>Bad Gateway</html>'),
          ),
        );

        expect(failure, isA<ServerFailure>());
        expect(failure.message, isNot(contains('<html>')));
      },
    );

    test('ignores non-string field errors rather than coercing them', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 422,
          requestOptions: RequestOptions(path: '/test'),
          response: problemResponse(422, const {
            'errors': {
              'tags': ['too many', 'not allowed'],
            },
          }),
        ),
      );

      expect((failure as ValidationFailure).fieldErrors, isEmpty);
    });
  });
}

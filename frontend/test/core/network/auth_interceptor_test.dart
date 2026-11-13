import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerpass/core/config/app_config.dart';
import 'package:peerpass/core/network/api_client.dart';
import 'package:peerpass/core/network/auth_interceptor.dart';
import 'package:peerpass/core/storage/token_store.dart';

/// Answers every request with the same status and an empty JSON body.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);

  final int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _config = AppConfig(
  apiBaseUrl: 'https://api.peerpass.test',
  connectTimeout: Duration(seconds: 5),
  receiveTimeout: Duration(seconds: 5),
  sendTimeout: Duration(seconds: 5),
);

void main() {
  late InMemoryTokenStore store;

  setUp(() => store = InMemoryTokenStore());

  test('a refresh that is refused does not ask for another refresh', () async {
    // The failure this guards against: `/v1/auth/refresh` going through the same
    // interceptor as every other call. A refused refresh is a `401`, which asked
    // the interceptor to refresh, which re-entered the single-flight it was
    // already inside and waited on itself forever. On device that looked like a
    // dead connection: the session never came back and nothing was logged.
    final adapter = _StatusAdapter(401);
    var refreshes = 0;

    late final Dio dio;
    dio = buildApiClient(
      config: _config,
      tokenStore: store,
      onUnauthorized: () async {
        refreshes++;
        await dio.post<void>('/v1/auth/refresh');
        return false;
      },
    )..httpClientAdapter = adapter;

    await expectLater(
      dio.post<void>(
        '/v1/auth/refresh',
        options: Options(extra: {AuthInterceptor.skipRefreshExtraKey: true}),
      ),
      throwsA(isA<DioException>()),
    );

    expect(refreshes, isZero);
  });

  test('an ordinary request that is refused does try a refresh', () async {
    // The other half of the rule: the opt-out must be narrow, or a session that
    // could have been renewed is reported as refused instead.
    final adapter = _StatusAdapter(401);
    var refreshes = 0;

    late final Dio dio;
    dio = buildApiClient(
      config: _config,
      tokenStore: store,
      onUnauthorized: () async {
        refreshes++;
        return false;
      },
    )..httpClientAdapter = adapter;

    await expectLater(
      dio.get<void>('/v1/sessions/me'),
      throwsA(isA<DioException>()),
    );

    expect(refreshes, 1);
  });
}

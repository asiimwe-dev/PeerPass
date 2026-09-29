import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:peerpass/core/config/app_config.dart';
import 'package:peerpass/core/network/auth_interceptor.dart';
import 'package:peerpass/core/storage/token_store.dart';

/// Builds the configured HTTP client.
///
/// Returns a client rather than a singleton so that tests can construct one
/// against a local server or a mock adapter without touching shared state.
Dio buildApiClient({
  required AppConfig config,
  required TokenStore tokenStore,
  TokenRefreshCallback? onUnauthorized,
}) {
  // Declared late so the retry closure can reference it. The closure only runs
  // after this function has returned, by which point the assignment has
  // happened, and a final field cannot be captured before it is initialised.
  late final Dio dio;

  dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      // Statuses are classified in `network_exceptions.dart`, so letting Dio
      // throw for every non-2xx keeps that logic in one place.
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );

  dio.interceptors
    ..add(
      AuthInterceptor(
        tokenStore: tokenStore,
        onUnauthorized: onUnauthorized,
        retry: (options) => dio.fetch<dynamic>(options),
      ),
    )
    ..add(_buildLoggingInterceptor());

  return dio;
}

Interceptor _buildLoggingInterceptor() {
  // Transport logging is a development aid only. It is disabled outside debug
  // builds, where the output would go to logcat on a device a student is
  // holding and into any `flutter logs` capture attached to a bug report.
  if (!kDebugMode) {
    return const Interceptor();
  }

  // Headers carry the Authorization bearer token, and every body in this API is
  // a credential or a student's academic record: sign-up carries a submitted
  // password, the auth responses carry issued tokens, and the rest carries
  // grades and session history. None of it goes to the device log.
  //
  // `requestBody` and `responseBody` are set even though dio already defaults
  // them to false, because that default is the only thing standing between a
  // debug build and a password in logcat, and it is one dio release away from
  // changing. A security-relevant default is worth stating where it is relied
  // on; the redundant-argument lint is silenced for the same reason.
  //
  // What is left is method, path, status and timing: enough to see that a
  // request went somewhere and came back, and nothing a student would mind
  // seeing pasted into a bug report.
  return LogInterceptor(
    requestHeader: false,
    responseHeader: false,
    // Matches the current dio default, but stated here on purpose: the default
    // is the only thing keeping a submitted password out of logcat, and a
    // review that reads the argument list should not have to know that.
    // ignore: avoid_redundant_argument_values
    requestBody: false,
    // As above. Response bodies here carry issued access and refresh tokens.
    // ignore: avoid_redundant_argument_values
    responseBody: false,
    logPrint: (object) => debugPrint(object.toString()),
  );
}

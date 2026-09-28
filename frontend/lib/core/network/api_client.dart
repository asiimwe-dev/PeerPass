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
  // Verbose transport logging is a development aid only. Headers are suppressed
  // because they carry the Authorization bearer token, which must not reach
  // logcat or the browser console on a device a student is holding.
  if (!kDebugMode) {
    return const Interceptor();
  }

  return LogInterceptor(
    requestHeader: false,
    responseHeader: false,
    logPrint: (object) => debugPrint(object.toString()),
  );
}

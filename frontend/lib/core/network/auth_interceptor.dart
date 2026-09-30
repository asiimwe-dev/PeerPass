import 'package:dio/dio.dart';
import 'package:peerpass/core/storage/token_store.dart';

/// Refreshes the access token, returning whether the session is still usable.
///
/// Supplied by the auth feature rather than implemented in `core/`, because
/// knowing how to refresh is a policy decision and `core/` must not import from
/// `features/`. This interceptor provides the transport; the feature provides
/// the decision.
typedef TokenRefreshCallback = Future<bool> Function();

/// Reissues a request through the configured client.
///
/// Supplied by `api_client.dart` because the retry has to go back out through
/// the same base URL, timeouts, and adapter. Declaring it here rather than
/// letting the interceptor hold the client keeps that reference one-directional.
typedef RequestRetryCallback = Future<Response<dynamic>> Function(
  RequestOptions options,
);

/// Attaches the bearer token and performs a single-flight refresh on `401`.
///
/// Refresh is single-flight because several requests can be in flight at once,
/// particularly on cold start when several screens hydrate together. Left
/// unguarded, each would independently present the refresh token, and all but
/// the first would be rejected as a replay of an already-rotated token, signing
/// the user out for no reason.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStore,
    required this.retry,
    this.onUnauthorized,
  });

  /// Where the bearer token is read from.
  final TokenStore tokenStore;

  /// Reissues the original request once the token has been refreshed.
  final RequestRetryCallback retry;

  /// Refresh strategy. When null, a `401` is passed through untouched.
  final TokenRefreshCallback? onUnauthorized;

  Future<bool>? _inFlightRefresh;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenStore.readAccessToken();
    if (token != null) {
      options.headers[_authorizationHeader] = '$_bearerPrefix $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final refresh = onUnauthorized;
    final recoverable =
        err.response?.statusCode == _statusUnauthorized &&
        err.requestOptions.extra[_retriedKey] != true &&
        refresh != null;

    if (!recoverable) {
      handler.next(err);
      return;
    }

    final refreshed = await (_inFlightRefresh ??= _refresh(refresh));
    // Release the memo either way. Holding it after a failure would replay the
    // same negative result for every later request in the session.
    _inFlightRefresh = null;

    if (!refreshed) {
      handler.next(err);
      return;
    }

    final token = await tokenStore.readAccessToken();
    final options = err.requestOptions
      ..extra[_retriedKey] = true
      ..headers[_authorizationHeader] = '$_bearerPrefix $token';

    try {
      handler.resolve(await retry(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<bool> _refresh(TokenRefreshCallback refresh) async {
    try {
      return await refresh();
    } on Object {
      // A transport error during refresh means the session could not be
      // renewed. The original 401 is the more useful error to surface, so the
      // refresh failure is absorbed rather than propagated in its place.
      return false;
    }
  }

  static const int _statusUnauthorized = 401;
  static const String _authorizationHeader = 'Authorization';
  static const String _bearerPrefix = 'Bearer';
  static const String _retriedKey = 'peerpass.retried_after_refresh';
}

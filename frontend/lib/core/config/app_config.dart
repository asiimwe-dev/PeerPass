import 'package:flutter/foundation.dart';

/// Build-time configuration for the client.
///
/// Values arrive through `--dart-define`, which keeps environment-specific
/// hosts out of version control: nothing here is hardcoded per deployment, and
/// no credential is ever compiled into a binary. Note that `--dart-define` is
/// resolved by the compiler, so switching environments requires a rebuild
/// rather than a runtime override.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.sendTimeout,
  });

  /// Reads configuration from the compile-time environment.
  ///
  /// Web runs in the browser, where `localhost` is the developer's machine.
  /// Android emulators instead need `10.0.2.2`; physical devices need an
  /// explicit LAN address. Deployed builds must provide an HTTPS URL.
  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000',
      ),
      connectTimeout: Duration(seconds: 10),
      receiveTimeout: Duration(seconds: 20),
      sendTimeout: Duration(seconds: 20),
    );
  }

  /// Root URL of the PeerPass API, without a trailing slash.
  final String apiBaseUrl;

  /// How long to wait for a TCP connection before giving up.
  final Duration connectTimeout;

  /// How long to wait for response bytes after the connection is established.
  final Duration receiveTimeout;

  /// How long to wait for the request body to be transmitted.
  final Duration sendTimeout;

  /// Whether the client is pointed at a locally served API.
  ///
  /// True when [apiBaseUrl] is plain HTTP, which in practice means a backend
  /// running on the developer's own machine. This exists to let development-only
  /// conveniences be scoped explicitly rather than inferred.
  ///
  /// It must not be used to weaken transport security. Certificate validation
  /// is unconditional: the client does not trust a self-signed server in
  /// development, because a debug-only bypass in a shared client is the usual
  /// way a production build ends up trusting anything. Reach a local HTTPS API
  /// through `adb reverse` or a trusted local certificate instead.
  bool get isLocalDevelopment => apiBaseUrl.startsWith('http://');
}

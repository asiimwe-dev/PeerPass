import 'package:flutter/foundation.dart';

/// Transport-independent representation of an error.
///
/// The presentation layer renders [Failure] and never a `DioException`, an
/// `SocketException`, or an HTTP status code. That keeps the UI unaware of Dio
/// and means swapping the HTTP client does not ripple into every screen.
///
/// [core/network/network_exceptions.dart] is responsible for translating
/// transport errors into these types. Because the hierarchy is sealed, an
/// exhaustive `switch` over a failure is a compile error when a new variant is
/// added, which is the point: adding a failure type should force every
/// presentation site to decide how to show it.
///
/// Implements [Exception] because these are thrown across the data/presentation
/// boundary and caught by screen code. A hierarchy that is thrown but is not an
/// [Exception] breaks the convention every `catch` and `on` clause in the
/// codebase relies on, and makes the lints that guard that convention fire at
/// every throw site.
sealed class Failure implements Exception {
  const Failure(this.message);

  /// Message safe to show to a user.
  ///
  /// Transport detail and stack information must not reach this field; it is
  /// rendered verbatim in the UI.
  final String message;
}

/// The request never reached the server, or the connection dropped.
///
/// Retryable by nature. Distinguishable from [ServerFailure] because the
/// remedy is different: this one succeeds on a second attempt from the same
/// device.
final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'No connection. Check your network and try again.',
  ]);
}

/// Credentials are missing, expired, or insufficient for the operation.
///
/// Not retryable without re-authenticating first.
final class AuthFailure extends Failure {
  const AuthFailure([
    super.message = 'Your session has ended. Please sign in again.',
  ]);
}

/// The server rejected the submitted values.
///
/// [fieldErrors] maps a form field name to the reason it was rejected, so a form
/// can render the message next to the input that caused it.
@immutable
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}});

  /// Per-field rejection reasons, keyed by the field name the API used.
  final Map<String, String> fieldErrors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationFailure &&
          other.message == message &&
          _mapEquals(other.fieldErrors, fieldErrors);

  @override
  int get hashCode => Object.hash(
    message,
    Object.hashAllUnordered(
      fieldErrors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// The requested resource does not exist, or is not visible to this user.
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'That item could not be found.']);
}

/// The request collided with existing state.
///
/// Raised when accepting a session that was already accepted or completed, which
/// is expected on a mobile client where a retried request is normal.
final class ConflictFailure extends Failure {
  const ConflictFailure([
    super.message = 'That has already changed. Refresh and try again.',
  ]);
}

/// The server failed to handle an otherwise valid request.
final class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Something went wrong on our end.']);
}

/// A request was cancelled before it completed, usually by navigation.
final class CancelledFailure extends Failure {
  const CancelledFailure([super.message = 'Request cancelled.']);
}

/// An error with no more specific classification.
///
/// Kept as a distinct type rather than collapsing into [ServerFailure] so that
/// "we do not know what this was" stays visible in logs rather than being
/// reported as a server fault.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something unexpected happened.']);
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

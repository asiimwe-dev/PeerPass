import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:peerpass/core/error/failures.dart';

/// Translates a transport error into a [Failure].
///
/// The only place in the client that knows Dio or `SocketException` exist.
/// Everything above this boundary works in terms of [Failure], which is what
/// lets the presentation layer stay free of HTTP concerns.
Failure mapDioException(DioException exception) {
  return switch (exception.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => const NetworkFailure(
      'The server took too long to respond. Try again.',
    ),
    DioExceptionType.connectionError => const NetworkFailure(),
    DioExceptionType.cancel => const CancelledFailure(),
    DioExceptionType.badCertificate => const NetworkFailure(
      'Could not establish a secure connection to the server.',
    ),
    DioExceptionType.badResponse => _mapResponse(exception.response),
    DioExceptionType.unknown => _mapUnknown(exception),
  };
}

/// A response that carried a status the client did not accept.
///
/// The API answers errors with RFC 9457 problem details, where `detail` is
/// human-readable text and `title` is a short summary. Classification keys off
/// the HTTP status rather than the `code` member: the status is the contract
/// this layer must handle exhaustively, whereas a problem `code` is free to be
/// added to without a client change.
Failure _mapResponse(Response<dynamic>? response) {
  if (response == null) {
    return const NetworkFailure();
  }

  final status = response.statusCode;
  if (status == null) {
    return const UnknownFailure();
  }

  final message = _problemDetail(response.data);
  final fieldErrors = _fieldErrors(response.data);

  return switch (status) {
    400 || 422 => ValidationFailure(
      message ?? 'Some of the details you entered are not valid.',
      fieldErrors: fieldErrors,
    ),
    401 || 403 => const AuthFailure(),
    404 => NotFoundFailure(message ?? 'That item could not be found.'),
    409 => ConflictFailure(
      message ?? 'That has already changed. Refresh and try again.',
    ),
    >= 500 => ServerFailure(
      message ?? 'Something went wrong on our end. Please try again.',
    ),
    _ => UnknownFailure(message ?? 'Something unexpected happened.'),
  };
}

/// The human-readable part of a problem details document, if it is one.
///
/// Returns null for any body that is not a problem details object, so a proxy
/// error page or an empty body falls through to the status-based default
/// message instead of being shown verbatim.
String? _problemDetail(Object? body) {
  if (body is! Map<String, dynamic>) return null;

  final detail = body['detail'];
  if (detail is! String || detail.isEmpty) return null;

  return detail;
}

/// The per-field errors in a problem details document, keyed by field name.
///
/// A form uses this to render each rejection next to the input that caused it.
/// Entries whose value is not a string are dropped rather than coerced, since
/// rendering `[object Object]` as a validation message helps nobody.
Map<String, String> _fieldErrors(Object? body) {
  if (body is! Map<String, dynamic>) return const {};

  final errors = body['errors'];
  if (errors is! Map<String, dynamic>) return const {};

  return {
    for (final entry in errors.entries)
      if (entry.value is String) entry.key: entry.value as String,
  };
}

/// An error with no response, where the cause is only visible in the inner
/// error. `SocketException` is separated out because "no connection" and
/// "certificate rejected" need different wording even though Dio reports both
/// as an unknown error.
Failure _mapUnknown(DioException exception) {
  final cause = exception.error;

  if (cause is SocketException) {
    return const NetworkFailure();
  }
  if (cause is TimeoutException) {
    return const NetworkFailure('The server took too long to respond.');
  }
  if (cause is FormatException) {
    return const ServerFailure('The server sent a response we could not read.');
  }

  return const UnknownFailure();
}

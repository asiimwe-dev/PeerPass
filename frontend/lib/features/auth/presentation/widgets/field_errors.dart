import 'package:peerpass/core/error/failures.dart';

/// The API's reason for rejecting one named field, if it gave one.
///
/// Returns null for a failure that is not a field-level rejection, and for a
/// field the API said nothing about. Both are ordinary: a student should not see
/// a stale error under an input the complaint was not about.
String? fieldErrorFor(Failure? failure, String field) {
  if (failure is! ValidationFailure) return null;
  return failure.fieldErrors[field];
}

/// The failure still worth showing as a banner, after the per-field messages.
///
/// Returns null when every part of the complaint has been placed next to the
/// input that caused it. Showing the same rejection twice -- once on the field and
/// once above the button -- reads as two separate problems.
Failure? bannerFailureFor(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure && failure.fieldErrors.isNotEmpty) return null;
  return failure;
}

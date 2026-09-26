/// Client-side checks for input a form can rule out before a round trip.
///
/// These exist only to spare the user a round trip on values the API would
/// reject anyway. The API remains the authority: every rule here is duplicated
/// server-side, and a client check that disagrees with the server is a bug, not
/// a shortcut. Nothing here encodes a business rule, only a shape constraint.
abstract final class Validators {
  /// Requires a value with at least one non-whitespace character.
  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  /// Bounds a value's length after trimming surrounding whitespace.
  static String? length(
    String? value, {
    required int min,
    required int? max,
    String field = 'This field',
  }) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length < min) {
      final exactly = min == 1
          ? 'at least $min character'
          : 'at least $min characters';
      return '$field must be $exactly';
    }
    if (max != null && trimmed.length > max) {
      return '$field must be at most $max characters';
    }
    return null;
  }

  /// Requires something that looks like an email address.
  ///
  /// Deliberately permissive: the only authority on whether an address exists
  /// is the confirmation mail, and an over-strict pattern rejects valid
  /// addresses on the way to finding that out.
  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email address is required';
    if (!_emailPattern.hasMatch(trimmed)) return 'Enter a valid email address';
    return null;
  }

  /// Requires a Ugandan mobile number in international or local form.
  ///
  /// The pilot is scoped to Uganda, so a bare seven-digit number is accepted
  /// with an implied `+256`; anything else must be written in full, because
  /// guessing a country code for an unknown number would silently route the
  /// student's session confirmations to the wrong place.
  static String? ugandanPhoneNumber(String? value) {
    final trimmed = (value?.trim() ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (trimmed.isEmpty) return 'Phone number is required';
    if (_localPhonePattern.hasMatch(trimmed)) return null;
    if (_internationalPhonePattern.hasMatch(trimmed)) return null;
    return 'Enter a valid Ugandan phone number, for example 0772 123 456';
  }

  /// Requires a password strong enough to survive a reused-credential list.
  ///
  /// Length is the only requirement, because it is the only property that
  /// reliably matters. Composition rules push students towards predictable
  /// substitutions, and the API enforces the real rule regardless.
  static String? password(String? value) {
    final lengthError = length(value, min: 8, max: null, field: 'Password');
    if (lengthError != null) return lengthError;
    return null;
  }

  /// Requires the two entries of a new-password form to agree.
  static String? passwordsMatch(String? password, String? confirmation) {
    if (confirmation == null || confirmation.isEmpty) {
      return 'Confirm your password';
    }
    if (password != confirmation) return 'Passwords do not match';
    return null;
  }

  /// Rejects a rating outside the one-to-five range the API accepts.
  static String? rating(int? value) {
    if (value == null) return 'Select a rating';
    if (value < 1 || value > 5) return 'Rating must be between 1 and 5';
    return null;
  }

  static final RegExp _emailPattern = RegExp(
    r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$',
  );
  static final RegExp _localPhonePattern = RegExp(r'^(0|256)?7\d{8}$');
  static final RegExp _internationalPhonePattern = RegExp(r'^\+2567\d{8}$');
}

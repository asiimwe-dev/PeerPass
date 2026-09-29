import 'package:flutter/material.dart';
import 'package:peerpass/core/utils/validators.dart';

/// The email and password pair, shared by sign-in and sign-up.
///
/// Shared because the two screens must agree about how a credential is entered
/// and about what "this field is wrong" looks like. If sign-in and sign-up each
/// built their own, a student registering after failing to sign in would meet a
/// differently-behaving form for the same problem.
class CredentialFields extends StatelessWidget {
  const CredentialFields({
    required this.emailController,
    required this.passwordController,
    required this.onChanged,
    this.emailError,
    this.passwordError,
    this.autofillHints = const <String>[],
    this.passwordLabel = 'Password',
    this.enabled = true,
    this.emailValidator = Validators.email,
    this.passwordValidator = Validators.password,
    super.key,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;

  /// Called on every keystroke in either field.
  ///
  /// The forms submit on a button press rather than a debounce, so they need
  /// every change to recompute whether the button is enabled.
  final VoidCallback onChanged;

  final String? emailError;
  final String? passwordError;

  /// Hints for the platform's password manager.
  ///
  /// Passed in because sign-up and sign-in want different values: registering
  /// wants a new password, signing in wants an existing one. Getting this wrong
  /// makes the system offer to generate a fresh password over an existing
  /// account.
  final List<String> autofillHints;

  final String passwordLabel;

  final bool enabled;

  /// Shape checks for the two fields.

  /// Parameters so a screen can add its own rule without this widget knowing
  /// why. Both default to the shared [Validators], which are duplicated from the
  /// API on purpose: the server stays the authority and these only spare a
  /// round trip on a value the API was going to reject.
  final FormFieldValidator<String> emailValidator;
  final FormFieldValidator<String> passwordValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: emailController,
          enabled: enabled,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: 'Email address',
            errorText: emailError,
            prefixIcon: const Icon(Icons.mail_outline),
          ),
          validator: emailValidator,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 16),
        _PasswordField(
          controller: passwordController,
          enabled: enabled,
          label: passwordLabel,
          error: passwordError,
          autofillHints: autofillHints,
          validator: passwordValidator,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A password field with a reveal toggle.
///
/// The toggle is not a convenience. Without it a student mistypes a password on
/// a phone keyboard with no way to see the typo, concludes the password is
/// wrong, and requests a reset -- so a two-second control removes a support
/// path.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.error,
    required this.autofillHints,
    required this.validator,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String? error;
  final List<String> autofillHints;
  final FormFieldValidator<String> validator;
  final VoidCallback onChanged;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autocorrect: false,
      obscureText: _obscured,
      autofillHints: widget.autofillHints,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.error,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscured = !_obscured),
          icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          tooltip: _obscured ? 'Show password' : 'Hide password',
        ),
      ),
      validator: widget.validator,
      onChanged: (_) => widget.onChanged(),
    );
  }
}

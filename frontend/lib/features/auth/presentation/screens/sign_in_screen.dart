import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// Placeholder for the sign-in screen.
///
/// Structure only. The form, validation wiring, and credential submission
/// arrive with the auth feature's implementation, at which point this file is
/// replaced rather than grown.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PeerPass', style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppDimens.sm),
                Text(
                  'Sign in is not implemented yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

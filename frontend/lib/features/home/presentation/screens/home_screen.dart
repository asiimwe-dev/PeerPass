import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// Placeholder for the signed-in landing screen.
///
/// Structure only. It exists so the router's authenticated branch is reachable
/// and testable, and it deliberately reads nothing from other features: the
/// session belongs to the auth feature, and reaching into that feature's
/// presentation layer from here would break the dependency rule the
/// architecture test enforces. The real content arrives with the home feature,
/// which will take what it needs through the auth repository contract.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.xl),
            child: Text(
              'Home is not implemented yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

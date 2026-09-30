import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// Placeholder for a screen that has nothing to show.
///
/// Distinct from a failure: an empty tutor list is a normal state, not an
/// error, and the copy differs accordingly.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;

  /// Optional explanation of what would fill this screen.
  final String? message;

  final IconData icon;

  /// Optional call to action, such as widening a search filter.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: AppDimens.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message case final text?) ...[
              const SizedBox(height: AppDimens.xs),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action case final widget?) ...[
              const SizedBox(height: AppDimens.lg),
              widget,
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';

/// Renders a [Failure] as something a student can act on.
///
/// Exists so no screen has to decide that a `NetworkFailure` deserves different
/// wording from a `ServerFailure`, and so the whole app fails the same way. The
/// pattern is an exhaustive switch, which means adding a failure type will not
/// compile until it has been given a presentation somewhere.
class FailureView extends StatelessWidget {
  const FailureView({required this.failure, this.onRetry, super.key});

  final Failure failure;

  /// Omitted when the operation cannot usefully be retried, such as a validation
  /// rejection, which will fail identically until the input changes.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(context), size: 40, color: theme.colorScheme.error),
            const SizedBox(height: AppDimens.md),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppDimens.lg),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _icon(BuildContext context) {
    return switch (failure) {
      NetworkFailure() => Icons.wifi_off_rounded,
      AuthFailure() => Icons.lock_outline_rounded,
      ValidationFailure() => Icons.edit_note_rounded,
      NotFoundFailure() => Icons.search_off_rounded,
      ConflictFailure() => Icons.sync_problem_rounded,
      ServerFailure() => Icons.cloud_off_rounded,
      CancelledFailure() => Icons.block_rounded,
      UnknownFailure() => Icons.error_outline_rounded,
    };
  }
}

import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/presentation/formatting.dart';

/// The bar and the numbers around it.
///
/// Split out of the screen so it can be rendered on its own in a test, and so
/// the screen is left holding only the three states a fetch can be in. The card
/// assumes there is something to show: the tutor-without-a-profile case is not
/// a progress bar at zero, it is a different screen, because a bar at zero
/// tells a student they are failing a requirement they have not been given a way
/// to meet.
class CertificateProgressCard extends StatelessWidget {
  const CertificateProgressCard({required this.eligibility, super.key});

  final CertificateEligibility eligibility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = remainingLabel(eligibility);
    final earned = eligibility.eligible;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Certificate progress',
                  style: theme.textTheme.titleMedium,
                ),
                if (earned)
                  const Chip(
                    label: Text('Earned'),
                    avatar: Icon(Icons.verified_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              // The value is known on the first build, so there is nothing to
              // animate from: the bar arrives at the number the API sent rather
              // than counting up to it, which would read as progress still
              // happening on a screen a tutor opened to check a total.
              child: LinearProgressIndicator(
                value: progressValue(eligibility),
                minHeight: AppDimens.sm,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppDimens.md),
            Text(
              certificateProgressLabel(eligibility),
              style: theme.textTheme.bodyLarge,
            ),
            if (remaining != null) ...[
              const SizedBox(height: AppDimens.xs),
              Text(
                remaining,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.md),
            const Divider(height: 1),
            const SizedBox(height: AppDimens.sm),
            // The certificate is three conditions, and the tutor is entitled to
            // see which one is holding them back rather than one bar that hides
            // the other two.
            for (final requirement in certificateRequirements(eligibility))
              _RequirementRow(requirement: requirement),
          ],
        ),
      ),
    );
  }
}

/// One condition, with the API's answer for it carried in the icon.
class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement});

  final CertificateRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final met = requirement.met;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: met
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppDimens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(requirement.label, style: theme.textTheme.bodyMedium),
                Text(
                  requirement.value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

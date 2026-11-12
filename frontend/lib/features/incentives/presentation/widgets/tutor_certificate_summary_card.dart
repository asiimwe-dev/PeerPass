import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/theme/app_palette.dart';
import 'package:peerpass/core/widgets/app_button.dart';
import 'package:peerpass/core/widgets/app_card.dart';
import 'package:peerpass/features/incentives/data/models/certificate_portfolio.dart';
import 'package:peerpass/features/incentives/presentation/formatting.dart';
import 'package:peerpass/features/incentives/presentation/providers/incentive_providers.dart';

/// The certificate section of a tutor's dashboard.
///
/// A compact restatement of the first course in the certificate portfolio, not a
/// second owner of the rule: the bar uses the API's `progress`, the label uses
/// its minutes, and the verdict is its `eligible`. The API orders the portfolio
/// earned first, then closest to earned, so "first" is also "the certificate
/// most worth showing".
///
/// A caller with no tutor profile is a different state, not a bar at zero. So is
/// a tutor with no verified course yet: they are on the path, and the card points
/// them at the applications screen rather than drawing a bar for a course they
/// have not started.
class TutorCertificateSummaryCard extends ConsumerWidget {
  const TutorCertificateSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(certificatePortfolioProvider);
    final failure = portfolio.hasError ? failureFor(portfolio.error!) : null;

    if (failure != null) {
      return _FailureNotice(
        message: failure.message,
        onRetry: () => ref.invalidate(certificatePortfolioProvider),
      );
    }

    final loaded = portfolio.value;
    if (loaded == null) return const _LoadingNotice();
    if (!loaded.hasTutorProfile) return const _NoProfileNotice();
    final course = loaded.leadingCourse;
    if (course == null) return const _NoCourseNotice();

    return _Progress(course: course);
  }
}

/// The bar and the numbers, sized for one dashboard section.
class _Progress extends StatelessWidget {
  const _Progress({required this.course});

  final CourseCertificate course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final remaining = remainingLabel(course);

    return AppCard(
      padding: const EdgeInsets.all(AppDimens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(course.courseUnitLabel, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.xxs),
          Text(
            'Certificate progress',
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
          const SizedBox(height: AppDimens.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            // The API already answered; animating up to the number would read as
            // work still happening on a total a tutor opened the card to check.
            child: LinearProgressIndicator(
              value: progressValue(course),
              minHeight: AppDimens.sm,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppDimens.md),
          Text(
            certificateProgressLabel(course),
            style: theme.textTheme.bodyLarge,
          ),
          if (remaining != null) ...[
            const SizedBox(height: AppDimens.xs),
            Text(
              remaining,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
          const SizedBox(height: AppDimens.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'View certificates',
              variant: AppButtonVariant.ghost,
              isFullWidth: false,
              isSmall: true,
              onPressed: () => context.push(AppRoutes.certificate),
            ),
          ),
        ],
      ),
    );
  }
}

/// The answer for an account that is not a tutor yet.
class _NoProfileNotice extends StatelessWidget {
  const _NoProfileNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppDimens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: palette.primary),
              const SizedBox(width: AppDimens.md),
              Expanded(
                child: Text(
                  'Certificate progress',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.md),
          Text(
            'Teaching hours will appear here once your tutor application is '
            'approved.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Apply to teach',
              variant: AppButtonVariant.ghost,
              isFullWidth: false,
              isSmall: true,
              onPressed: () => context.push(AppRoutes.tutorVerification),
            ),
          ),
        ],
      ),
    );
  }
}

/// The answer for a tutor who has no verified course yet.
class _NoCourseNotice extends StatelessWidget {
  const _NoCourseNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppDimens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: palette.primary),
              const SizedBox(width: AppDimens.md),
              Expanded(
                child: Text(
                  'Certificate progress',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.md),
          Text(
            'A certificate is earned per course. Once a course application is '
            'verified, its progress will appear here.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'View applications',
              variant: AppButtonVariant.ghost,
              isFullWidth: false,
              isSmall: true,
              onPressed: () => context.push(AppRoutes.myApplications),
            ),
          ),
        ],
      ),
    );
  }
}

/// The section while the answer is on its way.
class _LoadingNotice extends StatelessWidget {
  const _LoadingNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    return Semantics(
      liveRegion: true,
      child: AppCard(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              child: const LinearProgressIndicator(minHeight: AppDimens.sm),
            ),
            const SizedBox(height: AppDimens.md),
            Text(
              'Checking your certificate progress',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reason the card could not be filled, with the one action that helps.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppDimens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppDimens.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Try again',
              variant: AppButtonVariant.ghost,
              isFullWidth: false,
              isSmall: true,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

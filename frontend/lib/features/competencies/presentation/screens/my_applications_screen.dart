import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/competencies/data/models/application_limits.dart';
import 'package:peerpass/features/competencies/data/models/tutor_claim.dart';
import 'package:peerpass/features/competencies/data/repositories/competencies_repository.dart';
import 'package:peerpass/features/competencies/presentation/widgets/tutor_claim_status_chip.dart';

/// Every proof the signed-in user has submitted, and where each one stands.
///
/// This screen exists because a submission used to be a one-time message. The
/// API answered `pending`, the client threw the body away, showed a snackbar and
/// popped -- so a tutor who had applied had no way to find out whether an
/// operator had looked at it, and a tutor whose proof was refused had no way to
/// learn why. The endpoint behind it, `GET /v1/competencies/me`, existed the
/// whole time and was read by nothing.
///
/// Pull to refresh rather than a button, because the thing a tutor is waiting on
/// changes on someone else's schedule and the only honest way to check is to
/// ask again.
class MyApplicationsScreen extends ConsumerWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(myClaimsProvider);
    // Read separately from the claims list on purpose. A tutor can still read
    // where their applications stand when the limit endpoint is unreachable;
    // only the apply action becomes less specific.
    final limits = ref.watch(applicationLimitsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Tutor applications')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(myClaimsProvider)
            ..invalidate(applicationLimitsProvider);
          await Future.wait([
            ref.read(myClaimsProvider.future),
            ref.read(applicationLimitsProvider.future),
          ]);
        },
        child: claims.when(
          loading: () => const LoadingView(
            message: 'Loading your applications',
            variant: LoadingViewVariant.cards,
          ),
          error: (error, stackTrace) => _CenteredScroll(
            child: FailureView(
              // Every repository method throws a Failure, so this is normally a
              // message a tutor can read. An AsyncValue.error is typed Object,
              // so the one escape in the app is here: anything that is not a
              // Failure is something the client did not expect, and it says so
              // rather than showing raw exception text.
              failure: error is Failure ? error : const UnknownFailure(),
              onRetry: () => ref.invalidate(myClaimsProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _CenteredScroll(
                child: EmptyView(
                  title: 'You have not applied yet',
                  message:
                      'Submit proof of a grade to become a tutor. An operator '
                      'reviews it before you are listed for tutoring requests.',
                  icon: Icons.verified_user_outlined,
                  action: FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.tutorVerification),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Apply to teach'),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppDimens.screenPadding),
              children: [
                // The way back into the form for a tutor who is already teaching.
                // Before this existed, every apply entry disappeared once the
                // first claim was verified, so a tutor could never add a second
                // course. The count and the cap come from the API, and the same
                // limit is enforced there.
                _LimitCard(
                  limits: limits,
                  onApply: () => context.push(AppRoutes.tutorVerification),
                ),
                for (final claim in items) ...[
                  const SizedBox(height: AppDimens.md),
                  _ClaimCard(claim: claim),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Where the tutor stands against the application cap, and the way to use it.
///
/// [limits] is null when the limit endpoint could not be read. The apply action
/// is still offered then rather than hidden: the API enforces the same cap, so a
/// tutor with room should not be stopped by a screen that merely could not count.
class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.limits, required this.onApply});

  final ApplicationLimits? limits;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atCap = limits?.atCap ?? false;
    final remaining = limits?.remainingSlots;
    final openSlots = remaining == 1 ? 'One slot is' : '$remaining slots are';

    if (atCap) {
      return Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_clock_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: AppDimens.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Application limit reached',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: AppDimens.xxs),
                    Text(
                      'You are holding ${limits!.activeCount} of '
                      '${limits!.maxActiveCourseUnits} active course '
                      'applications. Wait for a reviewer to decide one before '
                      'applying for another course.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Teach another course', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppDimens.xxs),
            Text(
              limits == null
                  ? 'Submit proof for another course unit and an operator will '
                        'review it.'
                  : 'You have ${limits!.activeCount} of '
                        '${limits!.maxActiveCourseUnits} active course '
                        'applications. $openSlots open.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onApply,
                icon: const Icon(Icons.add),
                label: const Text('Apply for another course'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One claim, and everything a tutor needs to decide what to do about it.
class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.claim});

  final TutorClaim claim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The unit, then the grade claimed for it. Both are the API's
            // strings rather than anything joined here, so a unit whose code the
            // catalogue has since renamed reads the same on this screen as it
            // does on the admin console that judged it.
            Text(claim.courseUnitLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.xs),
            Text(
              'Claimed ${claim.gradeLabel}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.md),
            Row(
              children: [
                TutorClaimStatusChip(claim: claim),
                const SizedBox(width: AppDimens.sm),
                Expanded(
                  child: Text(
                    'Submitted ${_when(claim.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // The rejection reason, when there is one. This is the whole reason
            // the screen exists, so it is given its own row and its own emphasis
            // rather than being folded into the status chip where it would be a
            // second line of small text.
            if (claim.hasRejectionReason) ...[
              const SizedBox(height: AppDimens.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimens.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What to change',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: AppDimens.xxs),
                    Text(
                      claim.rejectionReason!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // A refusal with no recorded reason is a gap in the review, and the
            // honest thing to say is that rather than to imply the tutor did
            // something wrong.
            if (claim.isRejected && !claim.hasRejectionReason) ...[
              const SizedBox(height: AppDimens.md),
              Text(
                'No reason was recorded. Contact the operations team to ask why.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (claim.isRejected) ...[
              const SizedBox(height: AppDimens.md),
              OutlinedButton.icon(
                // Resubmission reopens the same record. The API refuses a unit
                // that still has a pending or verified claim, so the control is
                // offered exactly where that is not the case.
                onPressed: () => context.push(AppRoutes.tutorVerification),
                icon: const Icon(Icons.refresh),
                label: const Text('Submit different proof'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _when(DateTime moment) {
    final local = moment.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

/// A scrollable centre, so a failure or an empty state can be pulled.
///
/// [FailureView] and [EmptyView] are both unscrollable and centred, which puts
/// them out of reach of [RefreshIndicator] and traps a user who is offline
/// behind a Retry button they have to find. Wrapping them in a scroll view that
/// always overscrolls keeps pull-to-refresh available in every state.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

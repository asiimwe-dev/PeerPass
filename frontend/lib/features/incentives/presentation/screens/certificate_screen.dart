import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/presentation/providers/incentive_providers.dart';
import 'package:peerpass/features/incentives/presentation/widgets/certificate_progress_card.dart';

/// The signed-in user's own standing against the certificate threshold.
///
/// Its own screen rather than a card on the dashboard, because the answer is a
/// number with a history behind it and not a thing to read in passing: a tutor
/// opens this to find out how many more sessions they need, and a dashboard card
/// has nowhere to put "one more session" next to "four hours to go" without
/// either truncating one of them or pushing the rest of the dashboard down.
///
/// The progress bar is not duplicated onto the tutor rail or the public tutor
/// profile. Those are for other people to look at, this is the account's own
/// business, and a certificate threshold that appears on a profile page is one
/// line that can go stale on someone's cache.
///
/// Nothing here decides whether the tutor qualifies. The bar is drawn from the
/// API's `progress` and the verdict is its `eligible`; the only thing this screen
/// adds is what the numbers say in words.
class CertificateScreen extends ConsumerWidget {
  const CertificateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibility = ref.watch(certificateEligibilityProvider);
    final failure = eligibility.hasError ? failureFor(eligibility.error!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('My certificate')),
      body: SafeArea(
        child: Center(
          child: ContentWidthLimiter(
            child: switch ((failure, eligibility.value)) {
              (final failure?, _) => FailureView(
                failure: failure,
                onRetry: () => ref.invalidate(certificateEligibilityProvider),
              ),
              (null, final loaded?) => _Body(
                eligibility: loaded,
                // A callback rather than a `ref` inside `_Body`: pulling down to
                // refresh is the same action as the retry button, so both have to
                // be the one `invalidate` and cannot drift into two reloads that
                // mean slightly different things.
                onRefresh: () => ref.refresh(certificateEligibilityProvider.future),
              ),
              _ => const LoadingView(message: 'Checking your progress'),
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.eligibility, required this.onRefresh});

  final CertificateEligibility eligibility;

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    // A caller with no tutor profile is a real state with its own next step, so
    // it gets its own screen rather than a progress bar reading zero. A bar at
    // zero tells a student they are falling short of something they have not
    // been told how to reach, which is both untrue and a dead end.
    if (!eligibility.hasTutorProfile) {
      return EmptyView(
        icon: Icons.workspace_premium_outlined,
        title: 'You are not a tutor yet',
        message:
            'Once your tutor application is approved, the teaching hours that '
            'count towards a certificate will show here.',
        action: FilledButton(
          onPressed: () => context.push(AppRoutes.tutorVerification),
          child: const Text('Apply to teach'),
        ),
      );
    }

    return RefreshIndicator(
      // The numbers change as sessions are completed, and this screen is opened
      // to check them, so a stale answer here is worse than a stale list that
      // announces itself as a list.
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppDimens.screenPadding),
        children: [
          CertificateProgressCard(eligibility: eligibility),
          const SizedBox(height: AppDimens.xl),
          Text(
            'Only sessions you have completed count, and only up to the moment '
            'you mark them complete.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

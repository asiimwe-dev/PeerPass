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
import 'package:peerpass/features/incentives/data/models/certificate_portfolio.dart';
import 'package:peerpass/features/incentives/presentation/providers/incentive_providers.dart';
import 'package:peerpass/features/incentives/presentation/widgets/certificate_progress_card.dart';

/// The signed-in user's certificates, one per course.
///
/// A certificate is earned per course, so this is a list rather than one bar:
/// a tutor who teaches three courses has three separate records to build, and a
/// combined total would let one very long course carry the others over the bar.
///
/// Its own screen rather than a card on the dashboard, because the answer is a
/// set of numbers with a history behind them and not a thing to read in
/// passing: a tutor opens this to find out how many more sessions they need in
/// one specific course, and a dashboard card has nowhere to put that for every
/// course without either truncating it or pushing the rest of the dashboard
/// down.
///
/// Nothing here decides whether the tutor qualifies. The bar is drawn from the
/// API's `progress` and each verdict is its `eligible`; the only thing this
/// screen adds is what the numbers say in words.
class CertificateScreen extends ConsumerWidget {
  const CertificateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(certificatePortfolioProvider);
    final failure = portfolio.hasError ? failureFor(portfolio.error!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('My certificates')),
      body: SafeArea(
        child: Center(
          child: ContentWidthLimiter(
            child: switch ((failure, portfolio.value)) {
              (final failure?, _) => FailureView(
                failure: failure,
                onRetry: () => ref.invalidate(certificatePortfolioProvider),
              ),
              (null, final loaded?) => _Body(
                portfolio: loaded,
                // A callback rather than a `ref` inside `_Body`: pulling down to
                // refresh is the same action as the retry button, so both have to
                // be the one `invalidate` and cannot drift into two reloads that
                // mean slightly different things.
                onRefresh: () =>
                    ref.refresh(certificatePortfolioProvider.future),
              ),
              _ => const LoadingView(
                message: 'Checking your progress',
                variant: LoadingViewVariant.detail,
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.portfolio, required this.onRefresh});

  final CertificatePortfolio portfolio;

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    // A caller with no tutor profile is a real state with its own next step, so
    // it gets its own screen rather than a progress bar reading zero. A bar at
    // zero tells a student they are falling short of something they have not
    // been told how to reach, which is both untrue and a dead end.
    if (!portfolio.hasTutorProfile) {
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

    // A tutor with a profile but no verified course is on the path with nothing
    // to count yet. Saying so is the difference between an empty state and an
    // empty screen.
    if (portfolio.courses.isEmpty) {
      return EmptyView(
        icon: Icons.workspace_premium_outlined,
        title: 'No course certificate yet',
        message:
            'A certificate is earned per course, from completed sessions and '
            'ratings in that course. Once a course application is verified, its '
            'progress will show here.',
        action: FilledButton(
          onPressed: () => context.push(AppRoutes.myApplications),
          child: const Text('View my course applications'),
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
          for (final (index, course) in portfolio.courses.indexed) ...[
            if (index > 0) const SizedBox(height: AppDimens.lg),
            CertificateProgressCard(course: course),
          ],
          const SizedBox(height: AppDimens.xl),
          Text(
            'Each certificate counts only the sessions and ratings in its own '
            'course, and only sessions you have marked complete.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

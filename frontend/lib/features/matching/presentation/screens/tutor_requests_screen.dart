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
import 'package:peerpass/features/matching/data/models/help_request.dart';
import 'package:peerpass/features/matching/presentation/providers/matching_providers.dart';

/// The students who chose this tutor, waiting on them to answer.
///
/// The other half of the choice, and the reason the choice is a choice. A student
/// names one tutor; if that tutor is never told, the student waits on a decision
/// nobody was shown, and the platform's "the tutee picks, the tutor answers" is
/// only half implemented.
///
/// Two things this screen must not do, and each is the failure a matching client
/// usually has.
///
/// It must not show a request the tutor was not named on. The list is the API's
/// own scope, and adding to it client-side -- every open request, every
/// unconfirmed session -- would put a tutor's accept button next to work they
/// were never offered.
///
/// It must not create a session here. Confirming creates one, and a session is
/// the sessions feature's resource: its repository owns `POST /v1/sessions`, and
/// this screen calling it would be two features writing one endpoint. So the
/// confirm button navigates to a route the app router resolves to that feature's
/// screen, carrying the request's own values. What is expressed here is the
/// choice; where the session is made belongs to the feature that owns sessions.
///
/// Declining is a real decision and is recorded as one. It moves the request to a
/// state the student can read, and it is final: a second attempt is a new request,
/// which is what keeps the record of what was asked and refused intact.
class TutorRequestsScreen extends ConsumerWidget {
  const TutorRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(tutorRequestsProvider);
    final failure = requests.hasError ? failureFor(requests.error!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Waiting on you')),
      body: SafeArea(
        child: Center(
          child: ContentWidthLimiter(
            child: switch (failure) {
              // The retry is the invalidation rather than a bespoke reload, for
              // the reason the results screen does the same: one path for "ask
              // again", so a second one cannot drift from the first.
              final failure? => FailureView(
                failure: failure,
                onRetry: () => ref.invalidate(tutorRequestsProvider),
              ),
              null => switch (requests.value) {
                null => const LoadingView(message: 'Loading requests'),
                final loaded => _Requests(requests: loaded),
              },
            },
          ),
        ),
      ),
    );
  }
}

/// The list, including the case where there is nothing in it.
class _Requests extends StatelessWidget {
  const _Requests({required this.requests});

  final List<HelpRequest> requests;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      // An empty list is the ordinary answer for a tutor nobody has chosen yet,
      // not a failure. It gets its own copy rather than the generic empty state,
      // because "nothing here" reads as a broken screen unless it says what would
      // put something here.
      return RefreshIndicator(
        onRefresh: () => _reload(context),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: AppDimens.xxl),
            EmptyView(
              icon: Icons.inbox_rounded,
              title: 'No one is waiting on you',
              message:
                  'When a student asks you to tutor them, their request appears '
                  'here and you can turn it down.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      // The pull gesture, because a tutor who has been working elsewhere needs a
      // way to see a request that arrived while they were not looking, and a
      // screen that only loads once would not have it.
      onRefresh: () => _reload(context),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppDimens.lg),
        itemCount: requests.length,
        itemBuilder: (context, index) =>
            _TutorRequestCard(request: requests[index]),
      ),
    );
  }

  Future<void> _reload(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    // Invalidating and then awaiting the fresh read rather than returning at
    // once, so the spinner RefreshIndicator is holding stays up until the list is
    // actually new. A refresh that returns before the work it claims to have
    // started is how the gesture feels like it did nothing.
    return (container..invalidate(tutorRequestsProvider)).read(
      tutorRequestsProvider.future,
    );
  }
}

/// One request, and the one decision this screen can offer.
class _TutorRequestCard extends ConsumerWidget {
  const _TutorRequestCard({required this.request});

  final HelpRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final decision = ref.watch(tutorDecisionProvider(request.id));

    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.md),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.topic, style: theme.textTheme.titleMedium),
            if (request.description != null) ...[
              const SizedBox(height: AppDimens.sm),
              Text(
                request.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.md),
            Text(
              'Asked ${_when(request.createdAt)}. No time is set, and an '
              'unanswered request stays here until you answer it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (decision.failure != null) ...[
              const SizedBox(height: AppDimens.md),
              Text(
                decision.failure!.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.md),
            // Both decisions, and the ordering is the one the screen's own name
            // implies: most students who ask want the session, so confirming is
            // the filled button and declining is the outlined one beside it. A
            // tutor who genuinely cannot take it should not have to hunt for the
            // way out.
            //
            // Confirming navigates rather than calling anything. A session belongs
            // to the sessions feature -- its repository owns `POST /v1/sessions`,
            // and this feature reaching over would be two features writing one
            // endpoint. The route carries the request's own values so the form
            // does not have to fetch a request this list is already holding, and
            // the app router is the one layer allowed to import both features'
            // screens.
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: decision.submitting
                        ? null
                        : () => context.push(
                            AppRoutes.confirmRequestPath(
                              requestId: request.id,
                              courseUnitId: request.courseUnitId,
                              topic: request.topic,
                            ),
                          ),
                    child: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: AppDimens.md),
                Expanded(
                  child: OutlinedButton(
                    onPressed: decision.submitting
                        ? null
                        : () => ref
                              .read(tutorDecisionProvider(request.id).notifier)
                              .decline(),
                    child: Text(
                      decision.submitting ? 'Turning down…' : 'Turn down',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// When the student asked, in a form that does not need a date library.
  String _when(DateTime createdAt) {
    final local = createdAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month at $hour:$minute';
  }
}

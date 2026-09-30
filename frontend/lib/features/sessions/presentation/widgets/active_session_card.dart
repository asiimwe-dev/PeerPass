import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/presentation/formatting.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';
import 'package:peerpass/features/sessions/presentation/widgets/session_status_chip.dart';

/// The one session a student or tutor has to deal with right now, if any.
///
/// Placed above the pending tiles on home, and deliberately a *card* rather than a
/// section: home is a dashboard, and the thing that earns space there is a session
/// that is scheduled or live. Everything else about sessions -- the history, the
/// completed ones waiting for a rating -- is one tap away on the list screen and
/// stays there, because a dashboard that lists everything is a list with a
/// greeting above it.
///
/// Which session is shown is the API's ordering, narrowed to the live and
/// scheduled ones. The client does not decide that a tutor's first booking matters
/// more than a student's first one, and it cannot: the ordering rules live with the
/// data.
class ActiveSessionCard extends ConsumerWidget {
  const ActiveSessionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider);

    // The failure is checked before the value, and the order is the point: while
    // an error is standing, `value` is null, and a null session is also what "you
    // have no active sessions" looks like. Asking in the other order would swap
    // "could not ask" for "nothing to do" on every dropped connection.
    if (active.hasError) return const _LoadFailure();

    // Nothing while it loads, too. Home is not a loading state -- the rest of it
    // is already true -- and a card-shaped hole in the layout that jumps a second
    // later is worse than the card not being there yet. The list screen is where
    // waiting is shown.
    final session = active.value;
    if (session == null) return const SizedBox.shrink();

    return _SessionCard(session: session);
  }
}

/// The card itself: enough to recognise the session and get into it.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () => context.push(AppRoutes.sessionDetailPath(session.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SessionStatusChip(session: session),
                    const SizedBox(height: AppDimens.sm),
                    Text(session.topic, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppDimens.xxs),
                    Text(
                      sessionWhenLabel(session),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.sm),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// A failed fetch, in the size of a line rather than the size of a screen.
///
/// Home has other work to do, so this does not take the card's place with a
/// stack trace and a full-page retry. A tooltip rather than a text button, so the
/// home screen's own text is not crowded by another sentence on screen.
class _LoadFailure extends ConsumerWidget {
  const _LoadFailure();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(Icons.cloud_off_outlined, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppDimens.sm),
        Expanded(
          child: Text(
            "Couldn't load your sessions.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Retry sessions',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(sessionListProvider),
        ),
      ],
    );
  }
}

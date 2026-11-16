import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/presentation/formatting.dart';
import 'package:peerpass/features/sessions/presentation/widgets/session_status_chip.dart';

/// The heading a group of rows sits under.
class SessionSectionHeader extends StatelessWidget {
  const SessionSectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.lg,
        AppDimens.lg,
        AppDimens.lg,
        AppDimens.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One session in the list.
///
/// A `ListTile` rather than a card so the two sections on the sessions screen
/// read as one scrollable list. The status sits under the topic rather than in the
/// trailing slot because the trailing slot has the least room on a narrow phone
/// and "In progress" is exactly the label that must not be clipped.
class SessionTile extends StatelessWidget {
  const SessionTile({required this.session, required this.onTap, super.key});

  final SessionModel session;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      title: Text(
        session.topic,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppDimens.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SessionStatusChip(session: session),
            const SizedBox(height: AppDimens.xs),
            Text(
              sessionWhenLabel(session),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // A line rather than a badge in the trailing slot: the trailing slot
            // already holds the chevron, and on a narrow phone a pill there would
            // start clipping the topic. Unread is the one row that is allowed to
            // be taller, which is what makes it findable in a list.
            if (session.hasUnreadMessages) ...[
              const SizedBox(height: AppDimens.xs),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppDimens.xs),
                  Text(
                    'New message',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

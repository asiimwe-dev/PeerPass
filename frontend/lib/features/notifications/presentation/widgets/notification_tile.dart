import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/theme/app_palette.dart';
import 'package:peerpass/core/widgets/app_card.dart';
import 'package:peerpass/features/notifications/data/models/notification_model.dart';
import 'package:peerpass/features/notifications/presentation/formatting.dart';

/// One row in the inbox.
///
/// The whole card is the tap target, because the row has one job: open the thing
/// it is about. An unread row is tinted and carries a dot rather than only
/// bolding its title, so "new" survives a screenshot, a font override, and a
/// glance from across a room.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    required this.onTap,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final unread = notification.isUnread;

    return AppCard(
      padding: const EdgeInsets.all(AppDimens.lg),
      tint: unread ? palette.indigoTint : null,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(type: notification.type),
          const SizedBox(width: AppDimens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (unread) ...[
                      const SizedBox(width: AppDimens.sm),
                      Semantics(
                        label: 'Unread',
                        container: true,
                        child: Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: AppDimens.xs),
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppDimens.xs),
                Text(
                  notification.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
                const SizedBox(height: AppDimens.sm),
                Text(
                  relativeTimeLabel(notification.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
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

/// The small icon that says what kind of event this was.
///
/// Tone is semantic: amber is something to answer, mint is something completed,
/// coral is something that stopped. The glyph repeats the tone so the row is
/// readable without colour vision.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.type});

  final AppNotificationType type;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, background, foreground) = switch (type) {
      AppNotificationType.requestReceived => (
        Icons.help_outline_rounded,
        palette.amberTint,
        palette.onAmberTint,
      ),
      AppNotificationType.requestAccepted => (
        Icons.check_circle_outline_rounded,
        palette.mintTint,
        palette.onMintTint,
      ),
      AppNotificationType.requestDeclined => (
        Icons.block_rounded,
        palette.coralTint,
        palette.onCoralTint,
      ),
      AppNotificationType.sessionStarted => (
        Icons.play_circle_outline_rounded,
        palette.indigoTint,
        palette.onIndigoTint,
      ),
      AppNotificationType.sessionCompleted => (
        Icons.done_all_rounded,
        palette.mintTint,
        palette.onMintTint,
      ),
      AppNotificationType.sessionCancelled => (
        Icons.event_busy_rounded,
        palette.coralTint,
        palette.onCoralTint,
      ),
      AppNotificationType.ratingReceived => (
        Icons.star_outline_rounded,
        palette.amberTint,
        palette.onAmberTint,
      ),
      AppNotificationType.promotion => (
        Icons.workspace_premium_outlined,
        palette.mintTint,
        palette.onMintTint,
      ),
      AppNotificationType.messageReceived => (
        Icons.chat_bubble_outline_rounded,
        palette.indigoTint,
        palette.onIndigoTint,
      ),
      AppNotificationType.unknown => (
        Icons.notifications_none_rounded,
        palette.soft,
        palette.muted,
      ),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}

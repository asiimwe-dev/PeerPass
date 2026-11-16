import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/theme/app_palette.dart';
import 'package:peerpass/features/messages/data/models/session_message.dart';
import 'package:peerpass/features/messages/presentation/formatting.dart';

/// One line of a conversation, drawn on the side of whoever wrote it.
///
/// The side is the whole visual grammar of a chat: a reader sees at a glance
/// whether the plan they are looking at was theirs or the other person's, without
/// reading a name. [mine] is passed in rather than derived here because the
/// bubble does not know who is reading, and a widget that guessed would put the
/// other party's words on the wrong side.
///
/// No avatar and no sender name. In a two-person thread every message is from one
/// of two people and the side already says which; a name repeated above each line
/// is noise that costs a line of screen on a phone.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.mine,
    super.key,
  });

  final SessionMessage message;

  /// Whether the signed-in reader wrote this.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    final background = mine ? palette.primary : palette.soft;
    final foreground = mine ? palette.onPrimary : palette.ink;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.md,
        vertical: AppDimens.sm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppDimens.radiusMd),
          topRight: const Radius.circular(AppDimens.radiusMd),
          // The square corner sits under the tail of the bubble, on the side it
          // belongs to, which is what makes the two halves read as a dialogue
          // rather than as a list of cards.
          bottomLeft: Radius.circular(mine ? AppDimens.radiusMd : AppDimens.xs),
          bottomRight: Radius.circular(mine ? AppDimens.xs : AppDimens.radiusMd),
        ),
      ),
      child: Text(
        message.body,
        style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
      ),
    );

    final stamp = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          messageTimeLabel(message.createdAt),
          style: theme.textTheme.labelSmall?.copyWith(color: palette.muted),
        ),
        // Only the writer is told that the other side has read it. On a received
        // message the same flag would mean "you read this", which the reader
        // already knows and which would make their own reading look like an
        // acknowledgement they owe somebody.
        if (mine && message.isRead) ...[
          const SizedBox(width: AppDimens.xs),
          Icon(Icons.done_all_rounded, size: 14, color: palette.muted),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.xs),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          const SizedBox(height: AppDimens.xxs),
          stamp,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/theme/app_palette.dart';

/// Says that what is on screen came from the device rather than the server.
///
/// Deliberately not an error view, and deliberately short. The account is still
/// usable and the saved data is real; the one thing the student cannot see from
/// the screen itself is that it may have moved on since it was saved. One line
/// says that, and the app reconnects on its own; refresh is there for the times
/// the student wants to force it.
class OfflineNotice extends StatelessWidget {
  const OfflineNotice({
    this.message = 'No connection · showing saved data',
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.md,
          vertical: AppDimens.sm,
        ),
        decoration: BoxDecoration(
          color: palette.soft,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          border: Border.all(color: palette.line),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: palette.muted),
            const SizedBox(width: AppDimens.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

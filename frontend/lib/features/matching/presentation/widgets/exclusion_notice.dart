import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';
import 'package:peerpass/features/matching/presentation/formatting.dart';

/// Who the engine passed over, and why, in words.
///
/// This is the reason the API sends `exclusions` at all, and the reason the
/// screen reads them rather than dropping them: a student whose verified tutor
/// did not appear has no other way to find out what to fix, and a tutor who is
/// passed over with no explanation is the person the platform most needs to hear
/// from.
///
/// Rendered from the codes, never from prose the API does not send, and it says
/// so when it cannot: a code from a newer server than this client still produces
/// a line, which is the difference between "we could not say why" and a tutor who
/// silently vanished.
class ExclusionNotice extends StatelessWidget {
  const ExclusionNotice({required this.exclusions, super.key});

  final List<MatchExclusion> exclusions;

  @override
  Widget build(BuildContext context) {
    if (exclusions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tutors who were considered and left out',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppDimens.sm),
            for (final line in exclusionLines(exclusions))
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.xs),
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

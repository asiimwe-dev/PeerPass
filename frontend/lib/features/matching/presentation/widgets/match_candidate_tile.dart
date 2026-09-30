import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/tutor_standing.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';

/// One tutor the API is willing to propose, with the evidence behind it.
///
/// A vertical row rather than a rail card, because a candidate list is a list:
/// it is longer than a rail, it is read top to bottom, and each row carries the
/// unit's grade as well as the tutor. The rail's card would put the same four
/// fields in a 200pt box that the screen has the whole width for.
class MatchCandidateTile extends StatelessWidget {
  const MatchCandidateTile({required this.candidate, super.key});

  final MatchCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tutor = candidate.tutor;

    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.md),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tutor.fullName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: AppDimens.sm),
                _StandingChip(
                  standing: tutor.standing,
                  standingWire: tutor.standingWire,
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sm),
            Text(
              tutor.ratingLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              candidate.gradeLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tutor's standing, in the rail's colours.
///
/// A second copy of `TutorStandingChip`, on purpose. The dependency rules forbid
/// one feature importing another's presentation layer, and a chip is presentation;
/// the alternative -- the tutors feature reaching into core to hold a widget -- is
/// a decision about what `core/` is for, taken here on this feature's behalf. The
/// colour table is five lines and the standing itself is parsed once, in
/// `core/models/tutor_standing.dart`, so what can drift is a colour and not a
/// meaning.
class _StandingChip extends StatelessWidget {
  const _StandingChip({required this.standingWire, this.standing});

  final String standingWire;
  final TutorStanding? standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (standing) {
      TutorStanding.verified => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TutorStanding.probationary => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      TutorStanding.reduced => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      TutorStanding.suspended || null => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sm,
        vertical: AppDimens.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(
        standing?.label ?? standingWire,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

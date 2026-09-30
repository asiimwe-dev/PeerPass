import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/tutor_standing.dart';

/// A tutor's standing, labelled in words and coloured by how much it means.
///
/// The same shape as `SessionStatusChip`, deliberately: a rail card and a session
/// card sit on the same home screen, and two chips with the same job in two
/// shapes would be two things to keep consistent for no reason.
///
/// The colours are decoration, not meaning: a standing a user has to decode from
/// a colour is one they cannot read, which is why the label is always present.
/// An unrecognised standing falls back to the API's own word for it rather than
/// being hidden, so a state added after this release shows up as unfamiliar
/// instead of as no state at all.
class TutorStandingChip extends StatelessWidget {
  const TutorStandingChip({required this.standingWire, this.standing, super.key});

  /// The standing exactly as the API spelled it.
  final String standingWire;

  /// The parsed standing, or null when the API named one this client predates.
  final TutorStanding? standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = _colours(theme);

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

  (Color, Color) _colours(ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (standing) {
      // Verified is the standing the platform is trying to produce, so it is the
      // one that reads as the positive case.
      TutorStanding.verified => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TutorStanding.probationary => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      // Still eligible, ranked lower. Tertiary rather than an error colour: a
      // reduced tutor is not a problem, and colouring them like a suspension
      // would tell a student to avoid someone the API will still propose.
      TutorStanding.reduced => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      // A suspended tutor is excluded from matching, and the card says so.
      TutorStanding.suspended || null => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
  }
}

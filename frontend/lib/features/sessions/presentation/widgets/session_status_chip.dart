import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';

/// A session's status, labelled in words and coloured by how far along it is.
///
/// The colours are decoration, not meaning: a status a user has to decode from a
/// colour is a status they cannot read, which is why the label is always present.
/// An unrecognised status falls back to the API's own word for it rather than
/// being hidden, so a state added after this release shows up as unfamiliar
/// instead of as no state at all.
class SessionStatusChip extends StatelessWidget {
  const SessionStatusChip({required this.session, super.key});

  final SessionModel session;

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
        session.statusLabel,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }

  (Color, Color) _colours(ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (session.status) {
      TutoringSessionStatus.inProgress => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      TutoringSessionStatus.completed => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TutoringSessionStatus.scheduled => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      // Cancelled, a no-show, and anything this client does not recognise are all
      // states the session did not happen, and are coloured alike on purpose.
      TutoringSessionStatus.cancelled ||
      TutoringSessionStatus.noShow ||
      null => (scheme.errorContainer, scheme.onErrorContainer),
    };
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/tutors/data/models/tutor_detail.dart';
import 'package:peerpass/features/tutors/presentation/formatting.dart';
import 'package:peerpass/features/tutors/presentation/providers/tutor_providers.dart';
import 'package:peerpass/features/tutors/presentation/widgets/tutor_standing_chip.dart';

/// One tutor's public profile: standing, ratings, and what they are endorsed for.
///
/// Every field here is one the rail already carries, which is the point of the
/// API's shape: opening this screen costs one request and cannot reveal anything
/// the discovery list did not already show a student.
class TutorDetailScreen extends ConsumerWidget {
  const TutorDetailScreen({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(tutorDetailProvider(userId));
    final failure = detail.hasError ? failureFor(detail.error!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tutor')),
      body: SafeArea(
        child: Center(
          child: ContentWidthLimiter(
            child: switch (failure) {
              final failure? => FailureView(
                failure: failure,
                onRetry: () => ref.invalidate(tutorDetailProvider(userId)),
              ),
              null => switch (detail.value) {
                final loaded? => _Detail(detail: loaded),
                null => const LoadingView(message: 'Loading tutor'),
              },
            },
          ),
        ),
      ),
    );
  }
}

/// The profile, once it is here.
class _Detail extends ConsumerWidget {
  const _Detail({required this.detail});

  final TutorDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tutor = detail.profile;

    return ListView(
      padding: const EdgeInsets.all(AppDimens.lg),
      children: [
        Row(
          children: [
            CircleAvatar(
              // The pilot stores no images, so the placeholder is derived from
              // the name the API returned, on the same grounds as home's avatar.
              child: Text(_initials(tutor.fullName)),
            ),
            const SizedBox(width: AppDimens.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tutor.fullName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppDimens.xs),
                  TutorStandingChip(
                    standing: tutor.standing,
                    standingWire: tutor.standingWire,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.xl),
        _Stats(
          rating: tutor.ratingLabel,
          sessions: sessionsTaughtLabel(tutor.completedSessions),
          endorsements: _endorsementCountLabel(detail.endorsementCount),
        ),
        const SizedBox(height: AppDimens.xl),
        Text('Endorsed for', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppDimens.xs),
        Text(
          'Students who had a session with this tutor could say they covered '
          'these units.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppDimens.md),
        _EndorsedUnits(detail: detail),
      ],
    );
  }

  /// The first letters of the tutor's name, for the avatar placeholder.
  ///
  /// The first and the last word's initial, so "Achieng Grace Okello" reads as
  /// "AO" and not "AGO". Home's avatar does the same from the stored profile.
  static String _initials(String fullName) {
    final words = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return _initial(words.first);
    return '${_initial(words.first)}${_initial(words.last)}';
  }

  /// The first letter of a word, upper-cased.
  static String _initial(String word) => word[0].toUpperCase();

  /// How many endorsements in total, as a sentence.
  ///
  /// The true count rather than the number of units listed beside it: the API
  /// caps the list at five and sends the total separately for exactly this
  /// reason, so a tutor endorsed in fourteen units is not described as being
  /// endorsed five times.
  static String _endorsementCountLabel(int count) {
    if (count <= 0) return 'No endorsements yet';
    if (count == 1) return 'Endorsed once';
    return 'Endorsed $count times';
  }
}

/// The three counters, as a row rather than a list of labels.
class _Stats extends StatelessWidget {
  const _Stats({
    required this.rating,
    required this.sessions,
    required this.endorsements,
  });

  final String rating;
  final String sessions;
  final String endorsements;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Stat(label: 'Rating', value: rating)),
            const SizedBox(width: AppDimens.md),
            Expanded(child: _Stat(label: 'Sessions', value: sessions)),
            const SizedBox(width: AppDimens.md),
            Expanded(child: _Stat(label: 'Endorsements', value: endorsements)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppDimens.xxs),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// The endorsed units, named from the course-unit catalogue.
///
/// Reads the catalogue separately from the profile so a catalogue that will not
/// load costs the unit *codes* and nothing else: the standing, the rating and the
/// session count are already on screen by then, and a screen that replaced all
/// of them with a failure because an id could not be resolved would be throwing
/// away facts it already had.
class _EndorsedUnits extends ConsumerWidget {
  const _EndorsedUnits({required this.detail});

  final TutorDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalogue = ref.watch(courseUnitCatalogueProvider);

    // Loading is not rendered at all: the ids are on screen a moment later, and
    // a spinner under a heading reads as "there are none" until it resolves.
    final units = catalogue.value;
    if (units == null) {
      return _CatalogueProblem(
        message: catalogue.hasError
            ? 'The unit codes could not be loaded.'
            : 'Loading unit codes',
        onRetry: () => ref.invalidate(courseUnitCatalogueProvider),
        loading: !catalogue.hasError,
      );
    }

    final resolved = endorsedUnitsOf(detail, units);

    if (resolved.named.isEmpty) {
      return EmptyView(
        icon: Icons.workspace_premium_outlined,
        title: detail.endorsementCount == 0
            ? 'No endorsements yet'
            : 'Endorsement units are not listed here',
        message: detail.endorsementCount == 0
            ? 'Students who had a session with this tutor can endorse the '
                  'units it covered.'
            : 'This tutor has ${detail.endorsementCount} endorsements, and the '
                  'units behind them are not in the catalogue this device has.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppDimens.sm,
          runSpacing: AppDimens.sm,
          children: [
            for (final unit in resolved.named)
              Chip(label: Text('${unit.code} · ${unit.name}')),
          ],
        ),
        if (resolved.unresolved > 0) ...[
          const SizedBox(height: AppDimens.sm),
          Text(
            // Said rather than dropped. A sample of five with "and 9 more"
            // behind it is a claim the student can check; five units silently
            // standing in for fourteen is not.
            '${resolved.unresolved} more '
            '${resolved.unresolved == 1 ? 'unit is' : 'units are'} not in '
            'the catalogue this device has.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The catalogue's own state, in the size of a line.
class _CatalogueProblem extends StatelessWidget {
  const _CatalogueProblem({
    required this.message,
    required this.onRetry,
    required this.loading,
  });

  final String message;
  final VoidCallback onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return Row(
        children: [
          const SizedBox(
            width: AppDimens.lg,
            height: AppDimens.lg,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
          const SizedBox(width: AppDimens.md),
          Text(message, style: theme.textTheme.bodySmall),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Retry unit codes',
          icon: const Icon(Icons.refresh),
          onPressed: onRetry,
        ),
      ],
    );
  }
}

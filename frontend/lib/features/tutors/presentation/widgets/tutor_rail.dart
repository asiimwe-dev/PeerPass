import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/tutor_standing.dart';
import 'package:peerpass/core/theme/app_palette.dart';
import 'package:peerpass/core/widgets/app_avatar.dart';
import 'package:peerpass/core/widgets/app_card.dart';
import 'package:peerpass/core/widgets/app_pill.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';
import 'package:peerpass/features/tutors/presentation/formatting.dart';
import 'package:peerpass/features/tutors/presentation/providers/tutor_providers.dart';

/// How wide one rail card is.
///
/// A horizontal [ListView] hands its children an unbounded width and no way to
/// measure them, so a card has to be told. This is a layout constant and not a
/// spacing token, which is why it is not on `AppDimens`: `AppDimens` is the 4pt
/// gap scale and a 200pt card is not a gap.
const double _cardWidth = 200;

/// How tall one rail card is, for the same reason.
///
/// Tall enough for the avatar and name, a two-line bio, and the rating pill
/// without any of them being truncated into a second row of ellipses.
const double _cardHeight = 188;

/// The tutors to browse, as a rail of cards on the home screen.
///
/// Discovery, not matching. It ranks by what the API ranked by and proposes
/// nobody: `POST /v1/matching/suggestions` is the only thing that offers a tutor
/// for a unit, and a rail that implied otherwise would be answering a question
/// the student did not ask. Which is also why [courseUnitId] is a *filter* on a
/// rail of strong tutors and never a search that widens.
class TutorRail extends ConsumerWidget {
  const TutorRail({this.courseUnitId, super.key});

  /// Narrows the rail to tutors who pass the competency gate in this unit.
  ///
  /// Null, the default, is the whole-university rail the home screen shows. The
  /// API answers a unit it does not have with an empty list, so a stale value
  /// narrows the rail to nothing and says so rather than erroring.
  final String? courseUnitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rail = ref.watch(topTutorsProvider(courseUnitId));

    // The failure is checked before the value, and the order is the point: while
    // an error is standing, `value` is null, and an empty rail is also what "no
    // tutors yet" looks like. Asking in the other order would swap "could not
    // ask" for "nobody to show" on every dropped connection.
    final failure = rail.hasError ? failureFor(rail.error!) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tutors at your university', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppDimens.md),
        switch (failure) {
          final failure? => FailureView(
            failure: failure,
            onRetry: () => ref.invalidate(topTutorsProvider(courseUnitId)),
          ),
          null => switch (rail.value) {
            final loaded? =>
              loaded.isEmpty
                  ? const EmptyView(
                      icon: Icons.school_outlined,
                      title: 'No tutors to show yet',
                      message:
                          'Tutors appear here once they are verified in your '
                          'faculty. Nothing is wrong -- there are simply none '
                          'to recommend yet.',
                    )
                  : _TutorCards(
                      tutors: loaded,
                      isOffline: loaded.any((entry) => entry.isOfflineCached),
                    ),
            // Nothing at all while it loads. A rail-shaped hole that fills in a
            // moment later is honest; a spinner over the top of the home screen
            // would stall a dashboard whose other contents are already true.
            null => const LoadingView(
              message: 'Loading tutors',
              variant: LoadingViewVariant.cards,
            ),
          },
        },
      ],
    );
  }
}

/// The rail itself: cards, in the order the API sent them.
class _TutorCards extends StatelessWidget {
  const _TutorCards({required this.tutors, required this.isOffline});

  final List<TutorRailEntry> tutors;

  /// Whether the list is the device's last saved copy.
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isOffline) ...[
          Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 16, color: palette.muted),
              const SizedBox(width: AppDimens.xs),
              Expanded(
                child: Text(
                  'No connection · saved list',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sm),
        ],
        SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tutors.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppDimens.md),
            itemBuilder: (context, index) =>
                TutorCard(entry: tutors[index], width: _cardWidth),
          ),
        ),
      ],
    );
  }
}

/// One tutor, with enough on the card to recognise them and open their profile.
///
/// Everything here is on the API's rail entry already. The card asks for nothing
/// more, so opening the detail screen is a navigation rather than the moment a
/// card finally starts loading.
class TutorCard extends StatelessWidget {
  const TutorCard({required this.entry, required this.width, super.key});

  final TutorRailEntry entry;

  /// The width the rail hands this card.
  ///
  /// A parameter rather than a constant inside the card so the rail owns its
  /// layout and the card can be laid out somewhere else -- the matching
  /// candidate list is a vertical list and shares the fields but not the box.
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final tutor = entry.tutor;
    final isVerified = tutor.standing == TutorStanding.verified;

    return SizedBox(
      width: width,
      child: AppCard(
        padding: const EdgeInsets.all(AppDimens.lg),
        semanticLabel: 'Open ${tutor.fullName}',
        onTap: () => context.push(AppRoutes.tutorDetailPath(tutor.userId)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(
                  name: tutor.fullName,
                  imageUrl: tutor.avatarUrl,
                  size: 40,
                  isVerified: isVerified,
                ),
                const SizedBox(width: AppDimens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tutor.fullName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (tutor.yearLabel case final year?)
                        Text(
                          year,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sm),
            // A bio when there is one, the evidence otherwise. Both are the
            // same height so the card does not jump as a tutor writes one.
            Expanded(
              child: tutor.hasBio
                  ? Text(
                      tutor.bio!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sessionsTaughtLabel(tutor.completedSessions),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.muted,
                          ),
                        ),
                        Text(
                          entry.endorsementLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: AppDimens.sm),
            Row(
              children: [
                AppPill(
                  tutor.ratingLabel,
                  icon: Icons.star_rounded,
                  tone: tutor.hasRatings
                      ? AppPillTone.warning
                      : AppPillTone.neutral,
                  isCompact: true,
                ),
                const Spacer(),
                if (!tutor.acceptingRequests)
                  const AppPill(
                    'Paused',
                    icon: Icons.pause_rounded,
                    tone: AppPillTone.danger,
                    isCompact: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

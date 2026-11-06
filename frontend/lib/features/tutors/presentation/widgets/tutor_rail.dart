import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';
import 'package:peerpass/features/tutors/presentation/formatting.dart';
import 'package:peerpass/features/tutors/presentation/providers/tutor_providers.dart';
import 'package:peerpass/features/tutors/presentation/widgets/tutor_standing_chip.dart';

const double _cardWidth = 200;
const double _cardHeight = 148;

class TutorRail extends ConsumerWidget {
  const TutorRail({this.courseUnitId, super.key});
  final String? courseUnitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rail = ref.watch(topTutorsProvider(courseUnitId));
    final failure = rail.hasError ? failureFor(rail.error!) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CourseUnitSearch(
          onUnitSelected: (code) {
            ref.invalidate(topTutorsProvider(code));
          },
        ),
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
                  : _TutorCards(tutors: loaded),
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

class _CourseUnitSearch extends ConsumerWidget {
  const _CourseUnitSearch({required this.onUnitSelected});

  final void Function(String?) onUnitSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseUnits = ref.watch(courseUnitCatalogueProvider);
    final searchController = TextEditingController();
    return TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: 'Search course unit code (e.g. BCE2102)',
        border: const OutlineInputBorder(),
        suffixIcon: searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchController.clear();
                  onUnitSelected(null);
                },
              )
            : null,
      ),
      onChanged: (value) {
        final matched = courseUnits.value?.where(
          (unit) =>
              unit.code.toLowerCase().contains(value.toLowerCase()) ||
              unit.name.toLowerCase().contains(value.toLowerCase()),
        );
        if (matched?.isNotEmpty ?? false) {
          onUnitSelected(matched?.first.code);
        } else if (value.isNotEmpty) {
          onUnitSelected(null);
        }
      },
    );
  }
}

class _TutorCards extends StatelessWidget {
  const _TutorCards({required this.tutors});

  final List<TutorRailEntry> tutors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tutors.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppDimens.md),
        itemBuilder: (context, index) =>
            TutorCard(entry: tutors[index], width: _cardWidth),
      ),
    );
  }
}

class TutorCard extends StatelessWidget {
  const TutorCard({required this.entry, required this.width, super.key});

  final TutorRailEntry entry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tutor = entry.tutor;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.tutorDetailPath(tutor.userId)),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TutorStandingChip(
                  standing: tutor.standing,
                  standingWire: tutor.standingWire,
                ),
                const SizedBox(height: AppDimens.sm),
                Text(
                  tutor.fullName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppDimens.xxs),
                Text(
                  tutor.ratingLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  sessionsTaughtLabel(tutor.completedSessions),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  entry.endorsementLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

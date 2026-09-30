import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/course_unit.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/matching/data/models/match_result.dart';
import 'package:peerpass/features/matching/presentation/formatting.dart';
import 'package:peerpass/features/matching/presentation/providers/matching_providers.dart';
import 'package:peerpass/features/matching/presentation/widgets/exclusion_notice.dart';
import 'package:peerpass/features/matching/presentation/widgets/match_candidate_tile.dart';

/// Who the platform will propose for one course unit.
///
/// Three things this screen has to be careful about, and each one is a place a
/// matching client is usually wrong.
///
/// A widened answer is not an answer to the question that was asked. When
/// [MatchResult.widened] is true, nobody teaches the unit and these tutors teach
/// the subject around it, so the list is shown under a notice that says so in
/// words. Returning a widened list as though it were exact is the worst outcome
/// this screen could produce: the student would book a tutor who has never
/// opened a textbook for their course.
///
/// "Nobody is eligible" is a result, not a failure. It arrives as a successful
/// response carrying [MatchResult.noEligibleTutors], and it gets the empty
/// state -- an empty state that names the unit and points at the reasons below it
/// -- where a dropped connection gets [FailureView]. The two are different claims
/// about the world and must not wear the same face.
///
/// The reasons are shown whether or not anybody was proposed. A tutor excluded
/// for an unverified grade is the answer to "why is my friend not on this list",
/// and hiding that while showing the two who did qualify would be a strange
/// place to be coy.
class MatchResultsScreen extends ConsumerStatefulWidget {
  const MatchResultsScreen({required this.courseUnitId, super.key});

  /// The unit to find tutors for, as a public id from the route.
  final String courseUnitId;

  @override
  ConsumerState<MatchResultsScreen> createState() => _MatchResultsScreenState();
}

class _MatchResultsScreenState extends ConsumerState<MatchResultsScreen> {
  /// Whether to fall back to the whole subject when this unit has nobody.
  ///
  /// Off by default, which is the API's documented default and the safer reading:
  /// widening by default would answer a question the student did not ask. It is a
  /// switch rather than a fixed behaviour because the student is the only one who
  /// knows whether a tutor from the same subject is better than no tutor at all.
  bool _widenToSubject = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogueState = ref.watch(courseUnitOptionsProvider);
    final catalogue = catalogueState.value;
    final unitLabel = _unitLabel(catalogue);

    final results = ref.watch(
      matchResultsProvider((
        courseUnitId: widget.courseUnitId,
        widenToSubject: _widenToSubject,
      )),
    );
    final failure = results.hasError ? failureFor(results.error!) : null;

    return Scaffold(
      appBar: AppBar(title: Text(_titleFor(catalogue))),
      body: SafeArea(
        child: Center(
          child: ContentWidthLimiter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.lg,
                    AppDimens.md,
                    AppDimens.lg,
                    AppDimens.sm,
                  ),
                  child: _WidenToggle(
                    value: _widenToSubject,
                    onChanged: (value) =>
                        setState(() => _widenToSubject = value),
                  ),
                ),
                Expanded(
                  child: switch (failure) {
                    final failure? => FailureView(
                      failure: failure,
                      // Invalidating rather than a bespoke reload, so the button
                      // and the widening switch go through one path.
                      onRetry: () => ref.invalidate(
                        matchResultsProvider((
                          courseUnitId: widget.courseUnitId,
                          widenToSubject: _widenToSubject,
                        )),
                      ),
                    ),
                    null => switch (results.value) {
                      final loaded? => _Results(
                        result: loaded,
                        unitLabel: unitLabel,
                      ),
                      null => const LoadingView(message: 'Finding tutors'),
                    },
                  },
                ),
                // Kept outside the results so a catalogue that will not load
                // costs the unit's name, not the search: the fallback label still
                // says something true, and saying so is better than a title that
                // quietly says "Find a tutor" as though no unit had been chosen.
                if (catalogue == null && catalogueState.hasError)
                  Padding(
                    padding: const EdgeInsets.all(AppDimens.sm),
                    child: Text(
                      'The unit code could not be loaded.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What the unit is called, for the notice copy.
  ///
  /// Its code alone, because "Nobody teaches MAT 221 itself" is the sentence that
  /// says what went wrong, and the long name would only pad it. A catalogue that
  /// has not arrived leaves a label that still reads correctly.
  String _unitLabel(List<CourseUnit>? catalogue) {
    for (final unit in catalogue ?? const <CourseUnit>[]) {
      if (unit.publicId == widget.courseUnitId) return unit.code;
    }
    return 'this course unit';
  }

  /// The app bar's title, the same lookup with a whole-word fallback.
  String _titleFor(List<CourseUnit>? catalogue) {
    for (final unit in catalogue ?? const <CourseUnit>[]) {
      if (unit.publicId == widget.courseUnitId) {
        return '${unit.code} · ${unit.name}';
      }
    }
    return 'Find a tutor';
  }
}

/// The one search option a client may set, stated as a question.
///
/// Not hidden behind a menu because it changes what the list on the other side of
/// the screen means, and a student who did not know the search had widened would
/// read the results as being about their course.
class _WidenToggle extends StatelessWidget {
  const _WidenToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: const Text('Search the wider subject too'),
      subtitle: Text(
        value
            ? 'If nobody teaches this unit, tutors from the whole subject will '
                  'be listed as well.'
            : 'Only tutors who can be matched to this unit will be listed.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.sm),
    );
  }
}

/// The answer, however it came out.
class _Results extends StatelessWidget {
  const _Results({required this.result, required this.unitLabel});

  final MatchResult result;

  /// How the unit is named in the screen's copy.
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    // `noEligibleTutors` is read before the list, and the order matters: an empty
    // list under a widened notice is the API saying "nobody teaches this unit",
    // and rendering it as "no results" would leave a student wondering whether
    // the app had looked at the right course.
    if (result.noEligibleTutors) {
      return ListView(
        padding: const EdgeInsets.all(AppDimens.lg),
        children: [
          if (result.widened) ...[
            _WidenedNotice(unitLabel: unitLabel),
            const SizedBox(height: AppDimens.lg),
          ],
          EmptyView(
            icon: Icons.search_off_rounded,
            title: 'No eligible tutor for $unitLabel',
            message: noEligibleTutorsCopy(unitLabel),
          ),
          if (result.exclusions.isNotEmpty) ...[
            const SizedBox(height: AppDimens.lg),
            ExclusionNotice(exclusions: result.exclusions),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppDimens.lg),
      children: [
        if (result.widened) ...[
          _WidenedNotice(unitLabel: unitLabel),
          const SizedBox(height: AppDimens.lg),
        ],
        for (final candidate in result.candidates)
          MatchCandidateTile(candidate: candidate),
        if (result.exclusions.isNotEmpty) ...[
          const SizedBox(height: AppDimens.md),
          ExclusionNotice(exclusions: result.exclusions),
        ],
      ],
    );
  }
}

/// The banner that says the list is wider than the question.
class _WidenedNotice extends StatelessWidget {
  const _WidenedNotice({required this.unitLabel});

  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: AppDimens.md),
            Expanded(
              child: Text(
                widenedNotice(unitLabel),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

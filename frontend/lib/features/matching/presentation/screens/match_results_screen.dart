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
import 'package:peerpass/features/matching/presentation/widgets/request_topic_sheet.dart';

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
///
/// The list is a list of choices, not a reading. Each row asks to ask that tutor,
/// which sends the request and names them, and the screen then says what has
/// happened: "asked, not yet confirmed" rather than "booked". That distinction is
/// the whole point of the flow and the screen is where it is most likely to be
/// quietly lost -- a list that read as a booking list would have a student turning
/// up for a session no tutor had agreed to.
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

  /// Which tutor's request is in flight.
  ///
  /// Held here rather than in the controller because it is about this screen's
  /// rendering and changes the row that is busy, and the controller's own
  /// `submitting` cannot say *which* row. Null when nothing is being sent.
  String? _askingTutorId;

  TutorChoiceController get _choice =>
      ref.read(tutorChoiceProvider(widget.courseUnitId).notifier);

  /// Sends the request and names this tutor, then refreshes nothing.
  ///
  /// The sheet comes first and the request second, in that order, because a topic
  /// the student has not agreed to is not something to send and then ask about.
  /// A cancelled sheet returns null and is not an empty topic: nothing was sent,
  /// and treating it as an empty topic would be a request for a tutor to look at
  /// with nothing to look at.
  Future<void> _askTutor(MatchCandidate candidate) async {
    final draft = await showRequestTopicSheet(context);
    if (draft == null || !mounted) return;

    setState(() => _askingTutorId = candidate.tutor.userId);
    await ref
        .read(tutorChoiceProvider(widget.courseUnitId).notifier)
        .chooseTutor(
          topic: draft.topic,
          candidateTutorId: candidate.tutor.userId,
          tutorName: candidate.tutor.fullName,
          description: draft.description,
        );
    if (!mounted) return;
    setState(() => _askingTutorId = null);

    // The screen stays on the list rather than navigating away: the request may
    // exist even though the tutor was not named, and leaving would hide that from
    // the student. The banner reads the controller's failure and names the tutor,
    // so nothing is reported here as well.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogueState = ref.watch(courseUnitOptionsProvider);
    final catalogue = catalogueState.value;
    final unitLabel = _unitLabel(catalogue);
    final choice = ref.watch(tutorChoiceProvider(widget.courseUnitId));

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
                // A failure counts as something to report even with no request
                // behind it, which is the state a failed create leaves.
                if (choice.request != null || choice.failure != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.lg,
                    ),
                    child: _ChoiceBanner(
                      choice: choice,
                      onRefresh: _choice.refreshRequest,
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
                        choice: choice,
                        askingTutorId: _askingTutorId,
                        onAsk: _askTutor,
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
  const _Results({
    required this.result,
    required this.unitLabel,
    required this.choice,
    required this.askingTutorId,
    required this.onAsk,
  });

  final MatchResult result;

  /// How the unit is named in the screen's copy.
  final String unitLabel;

  /// What the student has already done about this unit.
  final TutorChoice choice;

  /// Which tutor's request is in flight, or null.
  final String? askingTutorId;

  /// Sends a request and names one of these tutors.
  final ValueChanged<MatchCandidate> onAsk;

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
        for (final candidate in result.candidates) _tileFor(candidate),
        if (result.exclusions.isNotEmpty) ...[
          const SizedBox(height: AppDimens.md),
          ExclusionNotice(exclusions: result.exclusions),
        ],
      ],
    );
  }

  /// One row, with its action decided by what the student has already done.
  ///
  /// The already-asked tutor keeps a control so the row does not change shape
  /// under the student, but it is a label rather than a button. A student who
  /// cannot see what happened to their request would reasonably tap again, and
  /// the API would refuse them for asking twice.
  Widget _tileFor(MatchCandidate candidate) {
    final tutorId = candidate.tutor.userId;
    final asked = choice.request?.matchedTutorId == tutorId;
    final busy = askingTutorId == tutorId || choice.submitting;

    return MatchCandidateTile(
      candidate: candidate,
      askLabel: asked
          ? tutorChosenCopy(candidate.tutor.fullName)
          : askTutorCopy(candidate.tutor.fullName),
      onAsk: asked || choice.submitting ? null : () => onAsk(candidate),
      busy: busy,
    );
  }
}

/// What became of the student's own request for this unit.
///
/// Three states and no fourth, because the API has three and inventing a fourth
/// on the client is how a student comes to believe a tutor agreed to something
/// nobody agreed to. A request the API has not been asked about does not get a
/// banner at all, because there is nothing true to say about it.
class _ChoiceBanner extends StatelessWidget {
  const _ChoiceBanner({required this.choice, required this.onRefresh});

  final TutorChoice choice;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final request = choice.request;
    final failure = choice.failure;

    // Read before the request, and shown whatever state the request is in. A
    // refusal with no request behind it -- the create call failed -- is exactly
    // the case that has no banner to hang a message on, and it is the one where
    // the student most needs to be told something: silently doing nothing after
    // they tapped Ask is indistinguishable from the app ignoring them.
    //
    // It also has to come before the states below rather than after, or a failed
    // second call is reported as a finished one: the request exists, so the
    // green "here is your request" banner would sit under a banner saying it
    // failed.
    if (failure != null) {
      final tutorName = choice.tutorName;
      return _Banner(
        icon: Icons.error_outline,
        message: tutorName == null
            ? failure.message
            : '${failure.message} ${choiceFailureHint(tutorName)}',
        tone: _BannerTone.problem,
        busy: choice.refreshing,
        // Nothing to re-read when there is no request to re-read, so the refresh
        // affordance is withheld rather than offered and doing nothing.
        onRefresh: choice.hasRequest ? onRefresh : null,
      );
    }

    if (request == null) return const SizedBox.shrink();

    if (choice.isDeclined) {
      return _Banner(
        icon: Icons.do_not_disturb_on_outlined,
        message: declinedCopy(request.topic),
        tone: _BannerTone.problem,
        busy: choice.refreshing,
        onRefresh: onRefresh,
      );
    }

    if (choice.isAwaitingTutor) {
      return _Banner(
        icon: Icons.hourglass_top_rounded,
        message: awaitingTutorCopy(request.topic),
        tone: _BannerTone.waiting,
        busy: choice.refreshing,
        onRefresh: onRefresh,
      );
    }

    return _Banner(
      icon: Icons.check_circle_outline,
      message: request.statusSentence,
      tone: _BannerTone.done,
      busy: choice.refreshing,
      onRefresh: onRefresh,
    );
  }
}

/// Which way round a banner reads.
enum _BannerTone { waiting, done, problem }

/// The banner's own face, so the three tones are one widget and not three.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    required this.tone,
    required this.busy,
    required this.onRefresh,
  });

  final IconData icon;
  final String message;
  final _BannerTone tone;
  final bool busy;

  /// Re-reads the request, or null where re-reading would say nothing new.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      _BannerTone.waiting => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _BannerTone.done => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _BannerTone.problem => (scheme.errorContainer, scheme.onErrorContainer),
    };

    return Card(
      color: background,
      margin: const EdgeInsets.only(bottom: AppDimens.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: AppDimens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (onRefresh != null) ...[
                    const SizedBox(height: AppDimens.sm),
                    TextButton.icon(
                      onPressed: busy ? null : () => onRefresh!(),
                      icon: busy
                          ? SizedBox.square(
                              dimension: AppDimens.md,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: foreground,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(busy ? 'Checking' : 'Check for an answer'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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

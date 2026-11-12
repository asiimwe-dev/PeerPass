import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/rating_tag.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/sessions/data/models/rating_model.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';

/// Every session the signed-in user is part of.
///
/// An [AsyncNotifier] rather than a plain controller because the only thing to do
/// with the list is load it, and [AsyncValue] already carries the three states a
/// list screen has to render: loading, the list, and the reason there is none.
/// A separate `loading` flag would be a second answer to a question the state
/// already answers, free to disagree with it.
///
/// Riverpod's automatic retry is switched off, which is a decision about *when to
/// ask again* rather than a domain rule. Its default is ten retries over about
/// thirty seconds, which would mean a screen that says "no connection, try again"
/// quietly re-requests underneath the user's finger -- replacing the message with a
/// spinner they did not ask for, on a screen that already has a button whose whole
/// job is this. The button, and the pull-to-refresh, are the retry.
final sessionListProvider =
    AsyncNotifierProvider<SessionListNotifier, List<SessionModel>>(
      SessionListNotifier.new,
      retry: (retryCount, error) => null,
    );

class SessionListNotifier extends AsyncNotifier<List<SessionModel>> {
  @override
  Future<List<SessionModel>> build() {
    return ref.read(sessionsRepositoryProvider).sessionsForMe();
  }
}

/// The one session the home screen's card shows.
///
/// Where it comes from, and why: the same list the sessions screen shows, so
/// there is one fetch and one answer. Out of the sessions that are still ahead of
/// the user -- scheduled or in progress -- a live one wins over a waiting one,
/// and among equals the API's own order decides, because
/// `GET /v1/sessions/me` returns them newest-created first and it is the only
/// party that knows how two overlapping sessions should be ranked for this user.
/// The client deliberately does not re-sort by `scheduled_start`: a second sort
/// here would be a second, divergent answer to a question the server has already
/// answered.
///
/// Derived rather than fetched, so a session that is ended or rated on the detail
/// screen changes this without a second request: the detail controller invalidates
/// [sessionListProvider] when it mutates anything, and this rebuilds from the new
/// list.
///
/// The automatic retry is off here for the same reason as on [sessionListProvider]:
/// this provider fails whenever the list does, so leaving it on would give the home
/// card its own invisible retry loop behind a message that already offers a button.
final activeSessionProvider = FutureProvider<SessionModel?>((ref) async {
  final sessions = await ref.watch(sessionListProvider.future);
  return activeSessionFrom(sessions);
}, retry: (retryCount, error) => null);

// Riverpod's family return type is not surfaced clearly enough for the analyzer
// to infer this declaration without an explicit annotation.
// ignore: specify_nonobvious_property_types
final receivedRatingProvider = FutureProvider.family<RatingModel?, String>((
  ref,
  sessionId,
) {
  final viewerId = ref.watch(sessionControllerProvider).profile?.publicId;
  final session = ref.watch(sessionDetailProvider(sessionId)).session;
  if (viewerId == null || session == null || !session.isTutor(viewerId)) {
    return null;
  }
  return ref
      .read(sessionsRepositoryProvider)
      .receivedRating(sessionId: sessionId);
});

/// Picks the session the home card shows out of [sessions].
///
/// A function rather than a line inside the provider so the choice is testable on
/// its own. See [activeSessionProvider] for why it is made this way.
SessionModel? activeSessionFrom(List<SessionModel> sessions) {
  SessionModel? waiting;
  for (final session in sessions) {
    if (!session.isActive) continue;
    if (session.status == TutoringSessionStatus.inProgress) return session;
    waiting ??= session;
  }
  return waiting;
}

/// One session, as the detail screen and the actions on it see it.
///
/// The state object rather than an `AsyncValue` of the session, because this
/// screen has two independent things to say: whether the session loaded, and
/// whether the *last action* on it worked. A refused check-in has to appear with
/// the session still on screen, so the two cannot share one value -- an
/// [AsyncError] would throw the session away to report a failed tap.
///
/// A submitted rating is held here so the tutee can see it immediately after
/// submission. Tutors read their received feedback through the scoped provider
/// below, rather than treating the session-level `is_rated` flag as their own
/// submission.
@immutable
class SessionDetailState {
  const SessionDetailState({
    this.session,
    this.loading = true,
    this.loadFailure,
    this.submitting = false,
    this.actionFailure,
    this.ratingGiven,
  });

  final SessionModel? session;

  final bool loading;

  /// Why the session could not be read.
  ///
  /// Kept apart from [actionFailure] because the two call for different remedies:
  /// a load that failed is worth retrying, and a refused check-in is not.
  final Failure? loadFailure;

  /// Whether an action on this session is in flight.
  final bool submitting;

  /// Why the last action was refused.
  final Failure? actionFailure;

  /// The rating this client submitted for this session, when it submitted one.
  final RatingModel? ratingGiven;

  SessionDetailState copyWith({
    SessionModel? session,
    bool? loading,
    Failure? loadFailure,
    bool? submitting,
    Failure? actionFailure,
    RatingModel? ratingGiven,
    bool clearLoadFailure = false,
    bool clearActionFailure = false,
  }) {
    return SessionDetailState(
      session: session ?? this.session,
      loading: loading ?? this.loading,
      // Explicit clears, for the same reason `OnboardingState` has them: "nothing
      // is wrong" is a state a `??` default cannot express.
      loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
      submitting: submitting ?? this.submitting,
      actionFailure: clearActionFailure
          ? null
          : (actionFailure ?? this.actionFailure),
      ratingGiven: ratingGiven ?? this.ratingGiven,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionDetailState &&
          other.session == session &&
          other.loading == loading &&
          other.loadFailure == loadFailure &&
          other.submitting == submitting &&
          other.actionFailure == actionFailure &&
          other.ratingGiven == ratingGiven;

  @override
  int get hashCode => Object.hash(
    session,
    loading,
    loadFailure,
    submitting,
    actionFailure,
    ratingGiven,
  );
}

/// One session, loaded on first read and mutated in place by its own actions.
///
/// A family keyed by the public id rather than one provider holding "the session
/// being looked at", because two of these can be alive at once -- the detail
/// screen and the rate screen below it -- and a single slot would make the second
/// screen overwrite the first one's state.
// Riverpod infers the family provider type from the generic parameters, and the
// analyzer does not surface that type in a way it can prove without the explicit
// ignore.
// ignore: specify_nonobvious_property_types
final sessionDetailProvider =
    NotifierProvider.family<
      SessionDetailController,
      SessionDetailState,
      String
    >(SessionDetailController.new);

class SessionDetailController extends Notifier<SessionDetailState> {
  SessionDetailController(this.sessionId);

  final String sessionId;

  SessionsRepository get _repository => ref.read(sessionsRepositoryProvider);

  @override
  SessionDetailState build() {
    // The detail belongs to whoever is signed in. Watching the viewer's id makes
    // the controller rebuild -- clearing a recorded rating and re-reading the
    // session -- when the account changes on this device, instead of handing
    // one student's submitted feedback to the next person who signs in.
    final viewerId = ref.watch(
      sessionControllerProvider.select((session) => session.profile?.publicId),
    );
    if (viewerId == null) {
      return const SessionDetailState(loading: false);
    }

    // Kicked off rather than awaited: `build` is synchronous, and awaiting inside
    // it would make the first frame wait on the network before anything is on
    // screen. Nothing writes to `state` before the first `await` below, because
    // Riverpod forbids changing a provider's state while it is being built.
    unawaited(_load());
    return const SessionDetailState();
  }

  /// Re-reads the session, for the retry button.
  Future<void> reload() async {
    state = state.copyWith(loading: true, clearLoadFailure: true);
    await _load();
  }

  /// Records this user's arrival, returning whether the tap was accepted.
  ///
  /// A second tap is idempotent on the server, so the screen does not need to
  /// remember whether it already asked. The session still only goes live when
  /// the other account checks in, and this returns the row either way so the
  /// screen can say who it is waiting for.
  Future<bool> checkIn() async {
    if (state.submitting) return false;
    state = state.copyWith(submitting: true, clearActionFailure: true);

    try {
      final checkedIn = await _repository.checkIn(sessionId: sessionId);
      if (!ref.mounted) return false;
      _adopt(checkedIn);
      return true;
    } on Object catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        submitting: false,
        actionFailure: failureFor(error),
      );
      return false;
    }
  }

  /// Records this user's departure, returning whether the tap was accepted.
  ///
  /// The first finish leaves the session in progress: the other party has not
  /// said they are done, and the API will not complete it on one person's word.
  Future<bool> finish() async {
    if (state.submitting) return false;
    state = state.copyWith(submitting: true, clearActionFailure: true);

    try {
      final finished = await _repository.finish(sessionId: sessionId);
      if (!ref.mounted) return false;
      _adopt(finished);
      return true;
    } on Object catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        submitting: false,
        actionFailure: failureFor(error),
      );
      return false;
    }
  }

  /// Records a rating this client submitted, so the screen can show it back.
  ///
  /// Called by the rate screen rather than by a shared "rated" flag, because the
  /// rating is the only part of the quality loop the client can still speak for.
  void recordRating(RatingModel rating) {
    state = state.copyWith(ratingGiven: rating);
    ref.invalidate(sessionListProvider);
  }

  /// Takes a session the API has just returned, and resettles everything that
  /// depends on the list.
  void _adopt(SessionModel session) {
    state = state.copyWith(
      session: session,
      submitting: false,
      clearActionFailure: true,
    );
    // The list carries the same rows and the home card is derived from it, so
    // leaving it stale would show a session as still running seconds after the
    // user ended it.
    ref.invalidate(sessionListProvider);
  }

  /// Reads the session, writing the result or the reason there is none.
  Future<void> _load() async {
    try {
      final session = await _repository.session(sessionId);
      // The screen can be popped while the request is in flight, and a provider
      // whose container has been torn down must not be written to.
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, session: session);
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadFailure: failureFor(error));
    }
  }
}

/// The rating being composed, before it is sent.
///
/// A draft, and kept as one for the reason the onboarding wizard's state is: the
/// score, the note and the endorsement are not stored anywhere until the student
/// submits, so a half-typed note that vanished on a rebuild would be a note the
/// student had to write twice. Nothing here decides whether a score is
/// *acceptable* -- the API bounds it, and the only rule here is that one has been
/// chosen at all.
@immutable
class RatingFormState {
  const RatingFormState({
    this.score,
    this.comprehensionHelped,
    this.feedback = '',
    this.endorsing = false,
    this.selectedTags = const [],
    this.submitting = false,
    this.failure,
  });

  /// The chosen score, or null before one is chosen.
  final int? score;

  final bool? comprehensionHelped;

  final String feedback;

  /// Whether the rater is also claiming the tutor covered the session's unit.
  ///
  /// Optional and off by default. A student who wants to say nothing more than a
  /// score should not be pushed into a claim about a tutor's coverage to get past
  /// a form, which is the failure the API documents this field as guarding
  /// against.
  final bool endorsing;

  /// The tags chosen so far, in the order they were picked.
  ///
  /// A list rather than a set because the order is sent to the API and shown on
  /// the profile: "patient, explained clearly" is what the student chose to say
  /// first, and a set would reorder it arbitrarily.
  final List<RatingTag> selectedTags;

  final bool submitting;

  final Failure? failure;

  /// Whether one more tag can be added.
  ///
  /// The API refuses a fifth. The form disables the remaining chips instead of
  /// letting the tap be rejected, so nobody types their way into an error.
  bool get canAddTag => selectedTags.length < maxRatingTags;

  /// Whether the submit button does anything.
  ///
  /// A rating is not optional in the sense of being skippable -- the API takes it
  /// whenever it is given -- but it cannot be sent without a score, so the button
  /// stays disabled until one is chosen rather than failing on tap.
  bool get canSubmit =>
      score != null && comprehensionHelped != null && !submitting;

  RatingFormState copyWith({
    int? score,
    bool? comprehensionHelped,
    String? feedback,
    bool? endorsing,
    List<RatingTag>? selectedTags,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return RatingFormState(
      score: score ?? this.score,
      comprehensionHelped: comprehensionHelped ?? this.comprehensionHelped,
      feedback: feedback ?? this.feedback,
      endorsing: endorsing ?? this.endorsing,
      selectedTags: selectedTags ?? this.selectedTags,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatingFormState &&
          other.score == score &&
          other.comprehensionHelped == comprehensionHelped &&
          other.feedback == feedback &&
          other.endorsing == endorsing &&
          listEquals(other.selectedTags, selectedTags) &&
          other.submitting == submitting &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(
    score,
    comprehensionHelped,
    feedback,
    endorsing,
    Object.hashAll(selectedTags),
    submitting,
    failure,
  );
}

/// The rating form for one session.
// The family provider's generic arguments are explicit enough for the controller,
// but the analyzer does not expose that as a concrete type for this property.
// ignore: specify_nonobvious_property_types
final ratingFormProvider =
    NotifierProvider.family<RatingFormController, RatingFormState, String>(
      RatingFormController.new,
    );

class RatingFormController extends Notifier<RatingFormState> {
  RatingFormController(this.sessionId);

  final String sessionId;

  @override
  RatingFormState build() => const RatingFormState();

  void chooseScore(int score) {
    if (state.submitting) return;
    state = state.copyWith(score: score, clearFailure: true);
  }

  void chooseComprehension({required bool helped}) {
    if (state.submitting) return;
    state = state.copyWith(comprehensionHelped: helped, clearFailure: true);
  }

  void writeFeedback(String value) {
    if (state.submitting) return;
    state = state.copyWith(feedback: value);
  }

  void setEndorsing({required bool value}) {
    if (state.submitting) return;
    state = state.copyWith(endorsing: value, clearFailure: true);
  }

  /// Adds a tag, or removes one that is already chosen.
  ///
  /// A fifth tag is ignored rather than replaced: swapping the oldest for the
  /// newest would make the chip the student did not tap disappear. The chips are
  /// disabled at the cap, so this guard is for a tap that raced a rebuild.
  void toggleTag(RatingTag tag) {
    if (state.submitting) return;
    final selected = List<RatingTag>.of(state.selectedTags);
    if (selected.remove(tag)) {
      state = state.copyWith(
        selectedTags: List<RatingTag>.unmodifiable(selected),
        clearFailure: true,
      );
      return;
    }
    if (selected.length >= maxRatingTags) return;
    selected.add(tag);
    state = state.copyWith(
      selectedTags: List<RatingTag>.unmodifiable(selected),
      clearFailure: true,
    );
  }

  /// Sends the rating, returning it when the API accepted one.
  ///
  /// Null means the API refused it, and [RatingFormState.failure] says why. The
  /// draft is kept on refusal so the student can fix the note and send it again
  /// without retyping the score.
  Future<RatingModel?> submit() async {
    final score = state.score;
    if (score == null || state.submitting) return null;

    state = state.copyWith(submitting: true, clearFailure: true);
    final note = state.feedback.trim();
    // The only unit an endorsement may name is the one the session was booked
    // for, and the service refuses anything else, so this sends that id or sends
    // nothing. A client cannot offer a list of units to endorse because the API
    // would reject every choice but the one it already knows.
    final courseUnitId = ref
        .read(sessionDetailProvider(sessionId))
        .session
        ?.courseUnitId;
    final endorsedCourseUnitIds = <String>[
      if (state.endorsing && courseUnitId != null) courseUnitId,
    ];

    try {
      final rating = await ref
          .read(sessionsRepositoryProvider)
          .rateSession(
            sessionId: sessionId,
            score: score,
            comprehensionHelped: state.comprehensionHelped!,
            // Omitted rather than sent empty: a blank note is the absence of a
            // note, and sending `''` would be a client asserting that the field
            // is empty rather than that it has nothing to say.
            feedbackText: note.isEmpty ? null : note,
            tags: [for (final tag in state.selectedTags) tag.wireValue],
            endorsedCourseUnitIds: endorsedCourseUnitIds,
          );
      if (!ref.mounted) return rating;
      // Handed to the detail screen so it can show the score back, then the list
      // is resettled so a completed session stops offering a rating.
      ref.read(sessionDetailProvider(sessionId).notifier).recordRating(rating);
      state = state.copyWith(submitting: false);
      return rating;
    } on Object catch (error) {
      if (!ref.mounted) return null;
      state = state.copyWith(submitting: false, failure: failureFor(error));
      return null;
    }
  }
}

/// The state of the form that turns a chosen help request into a session.
///
/// The one field the tutor fills in is how long the session is meant to last. The
/// request already carries the topic and the course unit, and neither is asked
/// for again: the student wrote the question, and the API checks the unit against
/// the request rather than trusting a value typed here. Asking the tutor to
/// retype either would invite a mismatch the server would then refuse, in front
/// of a tutor who did nothing wrong.
@immutable
class ConfirmRequestState {
  const ConfirmRequestState({
    this.durationMinutes = '',
    this.submitting = false,
    this.failure,
  });

  /// What has been typed, as text rather than as a number.
  ///
  /// A string because an empty field and the number zero are different states and
  /// the field has to be able to be empty. A `TextEditingController` would hold
  /// the text in the widget tree, which is rebuilt on every keystroke-driven
  /// setState, and this is the same reason [RatingFormState.feedback] is a string.
  final String durationMinutes;

  final bool submitting;

  final Failure? failure;

  /// The typed value as minutes, or null when it is not a whole positive number.
  ///
  /// Null rather than a guess. "60 minutes" and "sixty" both read as plausible to
  /// a person and only one of them is a number, and guessing at which the tutor
  /// meant is not this screen's decision to make. The API's own bounds are not
  /// restated here: it refuses a length it does not accept and names the field,
  /// and a client that hardcoded the range would be a second copy of a rule that
  /// changes without a deploy.
  int? get minutes {
    final parsed = int.tryParse(durationMinutes.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  bool get canSubmit => minutes != null && !submitting;

  ConfirmRequestState copyWith({
    String? durationMinutes,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return ConfirmRequestState(
      durationMinutes: durationMinutes ?? this.durationMinutes,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfirmRequestState &&
          other.durationMinutes == durationMinutes &&
          other.submitting == submitting &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(durationMinutes, submitting, failure);
}

/// The form that confirms one help request, keyed by the request's public id.
///
/// A [Notifier] family rather than screen state because the confirmation outlives
/// the widget for one good reason: it is an action the tutor can lose. The screen
/// is reachable by a route, the Android back gesture is one swipe away, and a
/// tutor who loses a typed length because of it would have to open the request
/// again. Keeping the draft here means returning to the route restores it.
// The family provider's generics are explicit, but the analyzer does not expose
// them as a concrete type for the declaration itself.
// ignore: specify_nonobvious_property_types
final confirmRequestProvider =
    NotifierProvider.family<
      ConfirmRequestController,
      ConfirmRequestState,
      String
    >(ConfirmRequestController.new);

class ConfirmRequestController extends Notifier<ConfirmRequestState> {
  ConfirmRequestController(this.requestId);

  final String requestId;

  @override
  ConfirmRequestState build() => const ConfirmRequestState();

  void writeDuration(String value) {
    if (state.submitting) return;
    state = state.copyWith(durationMinutes: value, clearFailure: true);
  }

  /// Confirms the request, returning the session the API created.
  ///
  /// Null means the API refused it and [ConfirmRequestState.failure] says why. The
  /// typed length is kept on refusal for the same reason the rating form keeps its
  /// note: the tutor should not have to retype it to try again.
  ///
  /// On success the session list is invalidated rather than patched in, because
  /// the created session belongs to the tutor and to the student and only the
  /// server knows what it looks like everywhere else. This screen hands the
  /// session back so the caller can open it directly.
  Future<SessionModel?> submit({
    required String courseUnitId,
    required String topic,
  }) async {
    final minutes = state.minutes;
    if (minutes == null || state.submitting) return null;
    state = state.copyWith(submitting: true, clearFailure: true);

    try {
      final created = await ref
          .read(sessionsRepositoryProvider)
          .confirmRequest(
            requestId: requestId,
            courseUnitId: courseUnitId,
            topic: topic,
            durationMinutes: minutes,
          );
      if (!ref.mounted) return created;
      ref.invalidate(sessionListProvider);
      state = state.copyWith(submitting: false);
      return created;
    } on Object catch (error) {
      if (!ref.mounted) return null;
      state = state.copyWith(submitting: false, failure: failureFor(error));
      return null;
    }
  }
}

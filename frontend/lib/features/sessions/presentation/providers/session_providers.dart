import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/sessions/data/models/rating_model.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';

/// The failure a screen may render for [error].
///
/// A provider can fail with something that is not a [Failure] -- a repository
/// override that was never registered is the one that happens in practice, and
/// the tests hit it whenever they do not care about sessions. The [Failure]
/// hierarchy is what the UI is written against, so anything else becomes an
/// [UnknownFailure] at this boundary rather than being rendered. Without it a
/// missing override would put `UnimplementedError: sessionsRepositoryProvider must
/// be overridden in ProviderScope.` on a student's home screen.
Failure failureFor(Object error) =>
    error is Failure ? error : const UnknownFailure();

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
final activeSessionProvider = FutureProvider<SessionModel?>(
  (ref) async {
    final sessions = await ref.watch(sessionListProvider.future);
    return activeSessionFrom(sessions);
  },
  retry: (retryCount, error) => null,
);

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
/// whether the *last action* on it worked. A wrong PIN has to appear under the
/// input that caused it with the session still on screen, so the two cannot share
/// one value -- an [AsyncError] would throw the session away to report a rejected
/// two-digit guess.
///
/// The rating is held here rather than re-read because there is no endpoint that
/// returns it: `GET /v1/ratings/me/recent` is ratings *received* by a tutor, and
/// `SessionResponse` carries only `is_rated`. So the score is known to the client
/// that submitted it, and only for as long as this state is alive.
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
  /// a load that failed is worth retrying, and a wrong PIN is not.
  final Failure? loadFailure;

  /// Whether an action on this session is in flight.
  final bool submitting;

  /// Why the last action was refused.
  final Failure? actionFailure;

  /// The rating this client submitted for this session, when it submitted one.
  final RatingModel? ratingGiven;

  /// Whether the last refusal was about the handshake pin.
  ///
  /// Read off the failure rather than remembered separately, so the two cannot
  /// disagree. The API answers a wrong pin with a 400 naming `pin` and nothing
  /// else, and that is the only rejection that belongs under the input rather
  /// than in a banner.
  bool get pinRejected =>
      actionFailure is ValidationFailure &&
      (actionFailure! as ValidationFailure).fieldErrors.containsKey('pin');

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
    NotifierProvider.family<SessionDetailController, SessionDetailState, String>(
      SessionDetailController.new,
    );

class SessionDetailController extends Notifier<SessionDetailState> {
  SessionDetailController(this.sessionId);

  final String sessionId;

  SessionsRepository get _repository => ref.read(sessionsRepositoryProvider);

  @override
  SessionDetailState build() {
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

  /// Submits the handshake pin, returning whether the session started.
  ///
  /// The value is checked by the API and by nothing else: no attempt counter, no
  /// lock-out, no client-side guess at how close the pin was. A student on a bad
  /// connection who mistypes twice must be able to try a third time, and a lock
  /// the device enforces is a lock they clear by reinstalling the app.
  Future<bool> submitPin(String pin) async {
    if (state.submitting) return false;
    state = state.copyWith(submitting: true, clearActionFailure: true);

    try {
      final started = await _repository.verifyPin(
        sessionId: sessionId,
        pin: pin,
      );
      if (!ref.mounted) return false;
      _adopt(started);
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

  /// Ends a live session, returning whether it ended.
  Future<bool> endSession() async {
    if (state.submitting) return false;
    state = state.copyWith(submitting: true, clearActionFailure: true);

    try {
      final completed = await _repository.endSession(sessionId);
      if (!ref.mounted) return false;
      _adopt(completed);
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
    this.feedback = '',
    this.endorsing = false,
    this.submitting = false,
    this.failure,
  });

  /// The chosen score, or null before one is chosen.
  final int? score;

  final String feedback;

  /// Whether the rater is also claiming the tutor covered the session's unit.
  ///
  /// Optional and off by default. A student who wants to say nothing more than a
  /// score should not be pushed into a claim about a tutor's coverage to get past
  /// a form, which is the failure the API documents this field as guarding
  /// against.
  final bool endorsing;

  final bool submitting;

  final Failure? failure;

  /// Whether the submit button does anything.
  ///
  /// A rating is not optional in the sense of being skippable -- the API takes it
  /// whenever it is given -- but it cannot be sent without a score, so the button
  /// stays disabled until one is chosen rather than failing on tap.
  bool get canSubmit => score != null && !submitting;

  RatingFormState copyWith({
    int? score,
    String? feedback,
    bool? endorsing,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return RatingFormState(
      score: score ?? this.score,
      feedback: feedback ?? this.feedback,
      endorsing: endorsing ?? this.endorsing,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatingFormState &&
          other.score == score &&
          other.feedback == feedback &&
          other.endorsing == endorsing &&
          other.submitting == submitting &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(score, feedback, endorsing, submitting, failure);
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

  void writeFeedback(String value) {
    if (state.submitting) return;
    state = state.copyWith(feedback: value);
  }

  void setEndorsing({required bool value}) {
    if (state.submitting) return;
    state = state.copyWith(endorsing: value, clearFailure: true);
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
            // Omitted rather than sent empty: a blank note is the absence of a
            // note, and sending `''` would be a client asserting that the field
            // is empty rather than that it has nothing to say.
            feedbackText: note.isEmpty ? null : note,
            endorsedCourseUnitIds: endorsedCourseUnitIds,
          );
      if (!ref.mounted) return rating;
      // Handed to the detail screen so it can show the score back, then the list
      // is resettled so a completed session stops offering a rating.
      ref
          .read(sessionDetailProvider(sessionId).notifier)
          .recordRating(rating);
      state = state.copyWith(submitting: false);
      return rating;
    } on Object catch (error) {
      if (!ref.mounted) return null;
      state = state.copyWith(submitting: false, failure: failureFor(error));
      return null;
    }
  }
}

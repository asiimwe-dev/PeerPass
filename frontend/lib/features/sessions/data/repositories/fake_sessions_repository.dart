import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/sessions/data/models/rating_model.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';

/// In-memory stand-in for the session and rating endpoints.
///
/// What widget tests resolve, because a widget test has no server to talk to. It
/// implements the repository's shape rather than the datasource's, because that
/// is the seam a test cares about: overriding the repository is the only
/// composition the app supports.
///
/// It is a fake and not a stub: a second check-in really starts the session, a
/// first finish really leaves it live, the second really completes it, and a
/// check-in on a cancelled session really fails. A fake that returned whatever it
/// was given would let a screen that never shows the failure -- or shows the wrong
/// one -- pass.
class FakeSessionsRepository implements SessionsRepository {
  FakeSessionsRepository({List<SessionModel> sessions = const []})
    : _sessions = List<SessionModel>.of(sessions);

  final List<SessionModel> _sessions;

  /// The signed-in user, as the API reads it from the access token.
  ///
  /// Check-in and finish record *one party's* timestamp, so the fake needs to
  /// know who is tapping. Set through [currentUser] by a widget test's pump
  /// helper, because the repository interface deliberately carries no user id:
  /// the real server takes it from the token, and a client that could name it
  /// would be able to check in for someone else.
  String? _currentUserId;

  /// The tutee a confirmed session is attributed to.
  ///
  /// Set by [withPendingStudent] rather than invented at the point of use, so a
  /// test that confirms a request can assert the resulting session belongs to the
  /// student who asked rather than to nobody.
  String _pendingTuteeId = 'student-1';

  /// The tutor a confirmed session is attributed to.
  String _pendingTutorId = 'tutor-1';

  /// The sessions the API would return, newest first.
  List<SessionModel> get sessions => List<SessionModel>.unmodifiable(_sessions);

  /// How many times the list has been asked for.
  ///
  /// A screen that reuses a keep-alive provider does not send a request, so this
  /// counter is how a test tells "re-read on entry" from "showed the old page".
  int listCalls = 0;

  /// Replaces the list the way the server would after something changed
  /// elsewhere: a thread was read, a session was finished on another phone.
  void replaceSessions(List<SessionModel> sessions) {
    _sessions
      ..clear()
      ..addAll(sessions);
  }

  /// Every rating submitted through this repository, in order.
  ///
  /// A test asserts on this to check what the rate screen actually sent, which is
  /// the only way to catch a screen that shows a score and submits a different
  /// one.
  final List<RatingModel> submittedRatings = [];

  /// The endorsed course unit ids of every submission, in order.
  ///
  /// Separate from [submittedRatings] because `RatingResponse` does not echo the
  /// endorsements back -- they are not part of the rating row -- so a test that
  /// only read the returned rating could not tell whether the endorsement went out
  /// at all.
  final List<List<String>> endorsementSubmissions = [];

  /// Every session id passed to [checkIn], in order.
  ///
  /// Recorded before the state check, so a screen test can prove the request was
  /// sent even when the API refused it.
  final List<String> checkedInSessionIds = [];

  /// Every session id passed to [finish], in order.
  final List<String> finishedSessionIds = [];

  /// What every [confirmRequest] was called with, in order.
  ///
  /// Recorded rather than inferred from the created session, so a test can assert
  /// on the duration the tutor actually typed. The created session echoes it, but
  /// only because this fake set it that way -- which is the thing under suspicion.
  final List<
    ({String requestId, String courseUnitId, String topic, int durationMinutes})
  >
  confirmations = [];

  /// Confirms a request the way the API does: refused unless it names a session
  /// that is already confirmed for that request.
  ///
  /// The refusal is modelled rather than stubbed because a double confirmation is
  /// the failure a phone actually produces, and a fake that always succeeded would
  /// let a screen ship a button that can be tapped twice into two sessions.
  @override
  Future<SessionModel> confirmRequest({
    required String requestId,
    required String courseUnitId,
    required String topic,
    required int durationMinutes,
  }) async {
    confirmations.add((
      requestId: requestId,
      courseUnitId: courseUnitId,
      topic: topic,
      durationMinutes: durationMinutes,
    ));

    final index = _sessions.indexWhere(
      (session) => session.helpRequestId == requestId,
    );
    if (index != -1) {
      throw const ConflictFailure(
        'This help request is not waiting for your answer.',
      );
    }
    if (durationMinutes < 1) {
      throw const ValidationFailure(
        'That length is not one the API accepts.',
        fieldErrors: {'duration_minutes': 'must be at least 1'},
      );
    }

    final created = SessionModel.fromJson({
      'id': 'session-from-$requestId',
      'tutee_id': _pendingTuteeId,
      'tutor_id': _pendingTutorId,
      'course_unit_id': courseUnitId,
      'course_unit_code': 'MAT 221',
      'course_unit_name': 'Linear Algebra',
      'tutee_name': 'Adongo Sarah',
      'tutor_name': 'Okello Daniel',
      'topic': topic,
      'status': 'scheduled',
      'duration_minutes': durationMinutes,
      'is_rated': false,
      'created_at': '2026-03-01T08:00:00Z',
      'help_request_id': requestId,
    });
    _sessions.add(created);
    return created;
  }

  /// Points the fake's confirmed sessions at a student and tutor.
  ///
  /// Returns nothing rather than `this`: a builder returning itself invites
  /// `FakeSessionsRepository()..withPendingStudent(...)` at a call site that then
  /// reads as though the value were new.
  void withPendingStudent(String tuteeId, {String? tutorId}) {
    _pendingTuteeId = tuteeId;
    if (tutorId != null) _pendingTutorId = tutorId;
  }

  /// The signed-in user the next [checkIn] or [finish] acts for.
  ///
  /// The API reads this from the access token; the fake cannot, because the
  /// repository contract has no user parameter on purpose. Tests set this from
  /// their pump helper so a tutor-side screen records the tutor's timestamp
  /// rather than guessing a party.
  String? get currentUser => _currentUserId;

  set currentUser(String publicId) {
    _currentUserId = publicId;
  }

  @override
  Future<List<SessionModel>> sessionsForMe() async {
    listCalls++;
    return sessions;
  }

  @override
  Future<SessionModel> session(String sessionId) async => _require(sessionId);

  @override
  Future<SessionModel> checkIn({required String sessionId}) async {
    checkedInSessionIds.add(sessionId);
    final session = _require(sessionId);
    if (session.status == TutoringSessionStatus.completed ||
        session.status == TutoringSessionStatus.cancelled ||
        session.status == TutoringSessionStatus.noShow) {
      throw const ConflictFailure(
        'This session is no longer open for check-in.',
      );
    }

    final viewerId = _viewerFor(session);
    // Already recorded: a retry answers 200 with the same row, because a phone
    // that missed the response must not be told its tap failed.
    if (session.hasCheckedIn(viewerId)) return session;

    final now = DateTime.now().toUtc();
    var updated = session.isTutor(viewerId)
        ? session.copyWith(tutorCheckedInAt: now)
        : session.copyWith(tuteeCheckedInAt: now);

    if (updated.tutorCheckedInAt != null && updated.tuteeCheckedInAt != null) {
      updated = updated.copyWith(
        status: TutoringSessionStatus.inProgress,
        statusWire: TutoringSessionStatus.inProgress.wireValue,
        startedAt: now,
      );
    }
    return _replace(updated);
  }

  @override
  Future<SessionModel> finish({required String sessionId}) async {
    finishedSessionIds.add(sessionId);
    final session = _require(sessionId);

    // A retried finish after completion returns the completed row unchanged, as
    // the API does, rather than banking the minutes a second time.
    if (session.status == TutoringSessionStatus.completed) return session;
    if (session.status != TutoringSessionStatus.inProgress) {
      throw const ConflictFailure(
        'Only a session both parties have checked in to can be finished.',
      );
    }

    final viewerId = _viewerFor(session);
    if (session.hasFinished(viewerId)) return session;

    final now = DateTime.now().toUtc();
    var updated = session.isTutor(viewerId)
        ? session.copyWith(tutorFinishedAt: now)
        : session.copyWith(tuteeFinishedAt: now);

    final tutorFinished = updated.tutorFinishedAt;
    final tuteeFinished = updated.tuteeFinishedAt;
    if (tutorFinished != null && tuteeFinished != null) {
      final started = updated.startedAt;
      if (started == null) {
        throw const ConflictFailure('This session has no recorded start.');
      }
      // The earlier departure, so a late tap cannot extend the hours -- the same
      // rule the API enforces.
      final ended = tutorFinished.isBefore(tuteeFinished)
          ? tutorFinished
          : tuteeFinished;
      final minutes = ended.difference(started).inMinutes;
      updated = updated.copyWith(
        status: TutoringSessionStatus.completed,
        statusWire: TutoringSessionStatus.completed.wireValue,
        endedAt: ended,
        durationMinutes: minutes < 1 ? 1 : minutes,
      );
    }
    return _replace(updated);
  }

  @override
  Future<RatingModel> rateSession({
    required String sessionId,
    required int score,
    required bool comprehensionHelped,
    String? feedbackText,
    List<String> tags = const [],
    List<String> endorsedCourseUnitIds = const [],
  }) async {
    final session = _require(sessionId);

    final rating = RatingModel(
      id: 'rating-$sessionId',
      sessionId: sessionId,
      // The API fills the rater and ratee in from the session rather than trusting
      // the body, so the fake derives them the same way: a tutee rates their
      // tutor, never the other way round.
      raterId: session.tuteeId,
      rateeId: session.tutorId,
      score: score,
      comprehensionHelped: comprehensionHelped,
      feedbackText: feedbackText,
      tags: List<String>.unmodifiable(tags),
      createdAt: DateTime.utc(2026, 3, 4, 9),
    );
    submittedRatings.add(rating);
    endorsementSubmissions.add(List<String>.of(endorsedCourseUnitIds));

    _replace(session.copyWith(isRated: true));
    return rating;
  }

  @override
  Future<RatingModel?> receivedRating({required String sessionId}) async {
    for (final rating in submittedRatings) {
      if (rating.sessionId == sessionId) return rating;
    }
    return null;
  }

  /// The signed-in user, refused unless they are one of the session's parties.
  ///
  /// An unset viewer is a test that forgot to set [currentUser], not a
  /// condition a server can produce, so it fails loudly with a [StateError]
  /// rather than pretending to be a party.
  String _viewerFor(SessionModel session) {
    final viewerId = _currentUserId;
    if (viewerId == null) {
      throw StateError(
        'FakeSessionsRepository.currentUser must be set before checkIn or '
        'finish.',
      );
    }
    if (!session.isTutee(viewerId) && !session.isTutor(viewerId)) {
      throw const AuthFailure('You do not have access to that session.');
    }
    return viewerId;
  }

  /// The session with [sessionId], or a failure the way the API would.
  SessionModel _require(String sessionId) {
    for (final session in _sessions) {
      if (session.id == sessionId) return session;
    }
    throw const NotFoundFailure('That session could not be found.');
  }

  /// Swaps a stored session for the version the API would now return.
  SessionModel _replace(SessionModel updated) {
    final index = _sessions.indexWhere((session) => session.id == updated.id);
    if (index != -1) _sessions[index] = updated;
    return updated;
  }
}

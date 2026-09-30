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
/// It is a fake and not a stub: the handshake really compares pins and the wrong
/// one really fails, the pin really moves the session to in-progress, and a rating
/// really marks the session rated. A fake that returned whatever it was given would
/// let a screen that never shows the failure -- or shows the wrong one -- pass.
class FakeSessionsRepository implements SessionsRepository {
  FakeSessionsRepository({List<SessionModel> sessions = const []})
    : _sessions = List<SessionModel>.of(sessions);

  final List<SessionModel> _sessions;

  /// The sessions the API would return, newest first.
  List<SessionModel> get sessions => List<SessionModel>.unmodifiable(_sessions);

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

  /// Every pin submitted through [verifyPin], in order.
  ///
  /// Kept so a test can prove a rejected pin was actually sent rather than
  /// refused by the client, and that a second attempt was still allowed.
  final List<String> pinAttempts = [];

  /// The sessions passed to [endSession], in order.
  final List<String> endedSessionIds = [];

  @override
  Future<List<SessionModel>> sessionsForMe() async => sessions;

  @override
  Future<SessionModel> session(String sessionId) async => _require(sessionId);

  @override
  Future<SessionModel> verifyPin({
    required String sessionId,
    required String pin,
  }) async {
    pinAttempts.add(pin);

    final session = _require(sessionId);
    final expected = session.sessionPin;
    // Fails closed the way the API does: a session with no stored pin rejects
    // every candidate, including a blank one.
    if (expected == null || expected.isEmpty || pin.trim() != expected) {
      throw const ValidationFailure(
        'The session PIN is incorrect.',
        fieldErrors: {'pin': 'incorrect'},
      );
    }

    return _replace(
      session.copyWith(
        status: TutoringSessionStatus.inProgress,
        statusWire: TutoringSessionStatus.inProgress.wireValue,
      ),
    );
  }

  @override
  Future<SessionModel> endSession(String sessionId) async {
    endedSessionIds.add(sessionId);
    return _replace(
      _require(sessionId).copyWith(
        status: TutoringSessionStatus.completed,
        statusWire: TutoringSessionStatus.completed.wireValue,
      ),
    );
  }

  @override
  Future<RatingModel> rateSession({
    required String sessionId,
    required int score,
    String? feedbackText,
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
      feedbackText: feedbackText,
      createdAt: DateTime.utc(2026, 3, 4, 9),
    );
    submittedRatings.add(rating);
    endorsementSubmissions.add(List<String>.of(endorsedCourseUnitIds));

    _replace(session.copyWith(isRated: true));
    return rating;
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

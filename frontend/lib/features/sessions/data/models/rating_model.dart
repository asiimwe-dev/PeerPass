import 'package:flutter/foundation.dart';

/// A rating one person gave another for a session.
///
/// The rater and the ratee are public ids rather than nested profiles, because
/// that is all `RatingResponse` carries and because a rating is read by its two
/// parties only: a student sees who rated a session of theirs, a tutor sees who
/// rated their teaching, and neither is shown to anyone else.
@immutable
class RatingModel {
  const RatingModel({
    required this.id,
    required this.sessionId,
    required this.raterId,
    required this.rateeId,
    required this.score,
    required this.createdAt,
    this.feedbackText,
  });

  /// Reads the wire form.
  ///
  /// Strict about everything a screen has to render and nothing else, for the
  /// reason given on `SessionModel.fromJson`: a [FormatException] becomes a
  /// server fault in the repository, where a bare cast error would not.
  ///
  /// The score is read as a number rather than as the wire string, because the
  /// API sends it as an integer. A score outside 1..5 is *not* rejected here: the
  /// database constrains it, and a client that refused to display a value the
  /// server chose would be inventing a second rule.
  factory RatingModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final sessionId = json['session_id'];
    final raterId = json['rater_id'];
    final rateeId = json['ratee_id'];
    final score = json['score'];
    final createdAt = json['created_at'];

    if (id is! String ||
        sessionId is! String ||
        raterId is! String ||
        rateeId is! String ||
        score is! num ||
        createdAt is! String) {
      throw const FormatException('rating response was missing a required field');
    }

    final feedback = json['feedback_text'];
    return RatingModel(
      id: id,
      sessionId: sessionId,
      raterId: raterId,
      rateeId: rateeId,
      score: score.toInt(),
      feedbackText: feedback is String && feedback.isNotEmpty ? feedback : null,
      createdAt: DateTime.parse(createdAt),
    );
  }

  final String id;

  final String sessionId;

  final String raterId;

  final String rateeId;

  /// The whole-number score, which the API bounds to 1..5.
  final int score;

  final String? feedbackText;

  final DateTime createdAt;

  /// The score as a student reads it back.
  String get scoreLabel => '$score out of 5';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatingModel &&
          other.id == id &&
          other.sessionId == sessionId &&
          other.raterId == raterId &&
          other.rateeId == rateeId &&
          other.score == score &&
          other.feedbackText == feedbackText &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    raterId,
    rateeId,
    score,
    feedbackText,
    createdAt,
  );

  @override
  String toString() => 'RatingModel($id, session: $sessionId, score: $score)';
}

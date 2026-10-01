import 'package:flutter/foundation.dart';

/// Where a help request stands, as the API spells it.
///
/// A code rather than a decision. What each status *means* for who may act on a
/// request is the API's rule, and re-deciding it here is how a client ends up
/// inviting a tutor to confirm something the server would refuse. All this
/// carries is the spelling and a sentence for a student or a tutor to read.
///
/// A code from a newer server than this client parses to null, and every screen
/// says what it can honestly say rather than guessing: "we could not say". The
/// alternative -- falling back to a status this client recognises -- would show a
/// request in a state it is not in, which is the one thing a status word must
/// never do.
enum HelpRequestStatus {
  open('open'),
  pendingConfirmation('pending_confirmation'),
  matched('matched'),
  declined('declined'),
  withdrawn('withdrawn'),
  expired('expired');

  HelpRequestStatus(this.wireValue);

  /// The value the API uses on the wire.
  final String wireValue;

  /// Whether the request is still one a tutor could be asked about.
  ///
  /// The tutor's list asks for [HelpRequestStatus.pendingConfirmation] from the
  /// API rather than filtering here, so this exists for the states a *student*
  /// is shown, where it decides whether the request is still live.
  bool get isLive => switch (this) {
    HelpRequestStatus.open || HelpRequestStatus.pendingConfirmation => true,
    HelpRequestStatus.matched ||
    HelpRequestStatus.declined ||
    HelpRequestStatus.withdrawn ||
    HelpRequestStatus.expired => false,
  };

  /// The status parsed from a wire code, or null when unrecognised.
  static HelpRequestStatus? fromWire(String? value) {
    for (final status in HelpRequestStatus.values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

/// A student's request for help, and who was chosen from the proposals.
///
/// The record of a choice rather than of a booking: [status] reaches
/// [HelpRequestStatus.pendingConfirmation] the moment a tutor is named, which is
/// before anyone has agreed to anything. A screen that treated this as "booked"
/// would be promising a student something the platform has not yet agreed to.
@immutable
class HelpRequest {
  const HelpRequest({
    required this.id,
    required this.tuteeId,
    required this.courseUnitId,
    required this.topic,
    required this.statusWire,
    required this.createdAt,
    this.description,
    this.status,
    this.matchedTutorId,
  });

  /// Reads one help request.
  ///
  /// [id], [courseUnitId] and [topic] are not defaulted: without them a screen
  /// could not say which question this is or answer it. [description] and
  /// [matchedTutorId] are, because a request that has not named a tutor yet is
  /// ordinary rather than malformed, and refusing the whole response over an
  /// absent optional field would hide a list of requests a student asked for.
  factory HelpRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final tuteeId = json['tutee_id'];
    final courseUnitId = json['course_unit_id'];
    final topic = json['topic'];
    final statusWire = json['status'];
    final createdAt = json['created_at'];

    if (id is! String ||
        id.isEmpty ||
        tuteeId is! String ||
        tuteeId.isEmpty ||
        courseUnitId is! String ||
        courseUnitId.isEmpty ||
        topic is! String ||
        topic.isEmpty ||
        statusWire is! String ||
        statusWire.isEmpty ||
        createdAt is! String) {
      throw const FormatException(
        'help request was missing its ids, topic, status, or time',
      );
    }

    final matchedTutorId = json['matched_tutor_id'];
    final description = json['description'];

    return HelpRequest(
      id: id,
      tuteeId: tuteeId,
      courseUnitId: courseUnitId,
      topic: topic,
      description: description is String ? description : null,
      statusWire: statusWire,
      status: HelpRequestStatus.fromWire(statusWire),
      // An absent tutor and a null one mean the same thing here: nobody has been
      // named yet. Anything else is not something a screen can act on, so it is
      // read as "nobody named", which under-claims rather than invents.
      matchedTutorId: matchedTutorId is String && matchedTutorId.isNotEmpty
          ? matchedTutorId
          : null,
      createdAt: DateTime.parse(createdAt),
    );
  }

  /// The request's public id, as the routes take it.
  final String id;

  /// The student who asked.
  ///
  /// Carried rather than inferred. A tutor's list is scoped to requests that
  /// named them, so the client knows this is another account, and a screen that
  /// wanted to name the student would need it -- but it is not a licence to fetch
  /// a profile it was not asked for.
  final String tuteeId;

  /// The unit help was asked for.
  final String courseUnitId;

  /// What the student needs, in their own words.
  final String topic;

  /// More detail, when the student gave any.
  final String? description;

  /// The status exactly as the API spelled it.
  final String statusWire;

  /// The parsed status, or null when the API used a code this client predates.
  final HelpRequestStatus? status;

  /// The tutor who was chosen, or null when nobody has been named.
  ///
  /// Nullable on purpose and not derived from [status]: a declined request keeps
  /// the tutor who said no, because the record of *who* turned it down is the
  /// part a student cannot reconstruct.
  final String? matchedTutorId;

  final DateTime createdAt;

  /// Whether a tutor has been named and has not yet answered.
  ///
  /// False for an unknown status: a request this client cannot read is not one to
  /// tell a student is still waiting.
  bool get isAwaitingTutor => status == HelpRequestStatus.pendingConfirmation;

  /// Whether the chosen tutor has said no.
  bool get isDeclined => status == HelpRequestStatus.declined;

  /// The status as a sentence for a student, or the honest answer.
  ///
  /// One place, because the student may read the same request in two places and
  /// two phrasings of one status is how a decline ends up described as a
  /// withdrawal.
  String get statusSentence => switch (status) {
    HelpRequestStatus.open => 'Waiting for you to choose a tutor.',
    HelpRequestStatus.pendingConfirmation =>
      'Sent to your chosen tutor. They have not confirmed yet.',
    HelpRequestStatus.matched => 'Your tutor confirmed. The session is booked.',
    HelpRequestStatus.declined => 'Your chosen tutor turned this request down.',
    HelpRequestStatus.withdrawn => 'You withdrew this request.',
    HelpRequestStatus.expired =>
      'This request expired before a tutor answered.',
    null => 'This request is in a state this version of the app does not know.',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HelpRequest &&
          other.id == id &&
          other.tuteeId == tuteeId &&
          other.courseUnitId == courseUnitId &&
          other.topic == topic &&
          other.description == description &&
          other.statusWire == statusWire &&
          other.matchedTutorId == matchedTutorId &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    tuteeId,
    courseUnitId,
    topic,
    description,
    statusWire,
    matchedTutorId,
    createdAt,
  );

  @override
  String toString() => 'HelpRequest($id, $statusWire)';
}

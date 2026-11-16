import 'package:flutter/foundation.dart';

/// Where a tutoring session has got to, as the API names the states.
///
/// Parsed from the wire rather than trusted as a string, and nullable on
/// [SessionModel] for the same reason `UserProfile` drops a role it does not
/// recognise: the API is still adding states (`no_show` arrived after the first
/// release), and a state this client has never heard of should render as an
/// unfamiliar label with no action attached rather than crash the sessions list
/// on launch. Which moves are legal is the API's business and is not encoded
/// here; this enum only says how a state is *displayed* and which of the two
/// lists on the sessions screen a row belongs in.
enum TutoringSessionStatus {
  scheduled('scheduled'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled'),
  noShow('no_show');

  TutoringSessionStatus(this.wireValue);

  /// The value the API uses on the wire.
  ///
  /// Held separately from [name] so renaming the Dart identifier cannot silently
  /// change what the client reads, and so a new case cannot be added without
  /// saying what the server calls it.
  final String wireValue;

  /// How the state is labelled to a student.
  ///
  /// A sentence rather than a bare token: the status is the one thing a user
  /// reads to decide what to do next, and "in_progress" is not that.
  String get label => switch (this) {
    scheduled => 'Scheduled',
    inProgress => 'In progress',
    completed => 'Completed',
    cancelled => 'Cancelled',
    noShow => 'No show',
  };

  /// Whether the session is still ahead of the user.
  ///
  /// Drives the Active/Past split on the sessions screen and nothing else. It is
  /// a grouping for display, deliberately not the transition table: the API
  /// decides which state may follow which, and a client that second-guessed it
  /// would offer a button the server then refuses.
  bool get isActive =>
      this == TutoringSessionStatus.scheduled ||
      this == TutoringSessionStatus.inProgress;

  /// The state parsed from a wire value, or null when it is not one we know.
  static TutoringSessionStatus? fromWire(String? value) {
    for (final status in TutoringSessionStatus.values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

/// A tutoring session, as the API returns it to either party.
///
/// A wire DTO and nothing more. The rules that decide what may happen to a
/// session -- who may start it, when it may be completed, whether a rating
/// exists -- live in the API, so this type carries no logic beyond "which of
/// the two parties is the reader", which is the one question a screen cannot
/// answer without asking the record.
@immutable
class SessionModel {
  const SessionModel({
    required this.id,
    required this.tuteeId,
    required this.tutorId,
    required this.courseUnitId,
    required this.courseUnitCode,
    required this.courseUnitName,
    required this.topic,
    required this.statusWire,
    required this.createdAt,
    this.tuteeName,
    this.tutorName,
    this.status,
    this.helpRequestId,
    this.scheduledStart,
    this.startedAt,
    this.endedAt,
    this.tutorCheckedInAt,
    this.tuteeCheckedInAt,
    this.tutorFinishedAt,
    this.tuteeFinishedAt,
    this.durationMinutes = 0,
    this.meetingLink,
    this.meetingVenue,
    this.meetingVenueDetail,
    this.isRated = false,
    this.unreadMessageCount = 0,
    this.isOfflineSnapshot = false,
  });

  /// Reads the wire form.
  ///
  /// The rule for tolerance: a field whose absence has one obvious neutral
  /// reading is defaulted, and a field a screen cannot render without is a
  /// [FormatException]. The id, the two parties, the unit, the topic, the status
  /// and the creation time are the ones a screen has nothing to fall back on;
  /// `is_rated` defaulting to false and `duration_minutes` to zero are both
  /// answers the API would give anyway, and a missing `scheduled_start` genuinely
  /// means an unscheduled session rather than a broken response.
  ///
  /// A [FormatException] here is a server fault, and the repository is what turns
  /// it into a user-facing failure: a bare cast error would arrive at a screen as
  /// a `TypeError`, get filed as an unknown error, and tell a student nothing.
  factory SessionModel.fromJson(Map<String, dynamic> json) {
    final id = _readId(json, 'id');
    final tuteeId = _readId(json, 'tutee_id');
    final tutorId = _readId(json, 'tutor_id');
    final courseUnitId = _readId(json, 'course_unit_id');
    final topic = json['topic'];
    final statusWire = json['status'];
    final courseUnitCode = json['course_unit_code'];
    final courseUnitName = json['course_unit_name'];

    if (id == null ||
        tuteeId == null ||
        tutorId == null ||
        courseUnitId == null ||
        topic is! String ||
        statusWire is! String) {
      throw const FormatException(
        'session response was missing a required field',
      );
    }

    if (courseUnitCode is! String || courseUnitName is! String) {
      throw const FormatException(
        'session response carried no course unit code and title',
      );
    }

    final createdAt = json['created_at'];
    if (createdAt is! String) {
      throw const FormatException('session response carried no creation time');
    }

    return SessionModel(
      id: id,
      tuteeId: tuteeId,
      tutorId: tutorId,
      courseUnitId: courseUnitId,
      courseUnitCode: courseUnitCode,
      courseUnitName: courseUnitName,
      tuteeName: _readString(json, 'tutee_name'),
      tutorName: _readString(json, 'tutor_name'),
      topic: topic,
      statusWire: statusWire,
      status: TutoringSessionStatus.fromWire(statusWire),
      createdAt: DateTime.parse(createdAt),
      helpRequestId: _readId(json, 'help_request_id'),
      scheduledStart: _readDateTime(json, 'scheduled_start'),
      startedAt: _readDateTime(json, 'started_at'),
      endedAt: _readDateTime(json, 'ended_at'),
      tutorCheckedInAt: _readDateTime(json, 'tutor_checked_in_at'),
      tuteeCheckedInAt: _readDateTime(json, 'tutee_checked_in_at'),
      tutorFinishedAt: _readDateTime(json, 'tutor_finished_at'),
      tuteeFinishedAt: _readDateTime(json, 'tutee_finished_at'),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      meetingLink: _readString(json, 'meeting_link'),
      meetingVenue: _readString(json, 'meeting_venue'),
      meetingVenueDetail: _readString(json, 'meeting_venue_detail'),
      isRated: switch (json['is_rated']) {
        final bool rated => rated,
        // Not a boolean. The field has one obvious neutral reading, and refusing
        // the whole session over it would be worse than reading it as unrated.
        _ => false,
      },
      // Absence means nothing unread, which is what an older server that does not
      // count messages at all would say, and what a session with no thread says
      // anyway. A client that refused the row over a missing badge would hide a
      // whole session to avoid drawing one number.
      unreadMessageCount: (json['unread_message_count'] as num?)?.toInt() ?? 0,
      isOfflineSnapshot: json['_offline_cached'] == true,
    );
  }

  final String id;

  final String tuteeId;

  final String tutorId;

  /// The unit's public id.
  ///
  /// Kept because the client identifies the unit by it. The code and title beside
  /// it are what a screen shows; an id is an identity, not a label.
  final String courseUnitId;

  /// The unit's code, as the catalogue spells it.
  ///
  /// Required with [courseUnitCode] rather than defaulted: the API projects both
  /// from the same row on every path, so a response missing one is a server fault
  /// worth reporting rather than a card with a blank line on it.
  final String courseUnitCode;

  /// The unit's title.
  final String courseUnitName;

  /// The student's display name, or null when the account has not set one.
  final String? tuteeName;

  /// The tutor's display name, or null when the account has not set one.
  final String? tutorName;

  /// The unit as a reader sees it: "MAT 221 · Linear Algebra".
  String get courseUnitLabel => '$courseUnitCode · $courseUnitName';

  final String topic;

  /// The status exactly as the API spelled it.
  ///
  /// Kept beside the parsed [status] so an unrecognised state can be shown to
  /// the user verbatim rather than as a blank or a guessed label.
  final String statusWire;

  /// The parsed status, or null when the API named one this client predates.
  final TutoringSessionStatus? status;

  final String? helpRequestId;

  final DateTime? scheduledStart;

  final DateTime? startedAt;

  final DateTime? endedAt;

  /// When the tutor independently tapped "I'm here", if they have.
  final DateTime? tutorCheckedInAt;

  /// When the student independently tapped "I'm here", if they have.
  final DateTime? tuteeCheckedInAt;

  /// When the tutor independently tapped "Finish", if they have.
  final DateTime? tutorFinishedAt;

  /// When the student independently tapped "Finish", if they have.
  final DateTime? tuteeFinishedAt;

  final int durationMinutes;

  /// The arrival timestamp for [publicId], or null when they have not joined.
  ///
  /// One lookup for the four timestamp columns so a screen never has to ask
  /// "which side am I?" and then index into a map of columns. Null for a viewer
  /// who is neither party, which a stale cached profile can produce.
  DateTime? checkedInAt(String publicId) {
    if (isTutor(publicId)) return tutorCheckedInAt;
    if (isTutee(publicId)) return tuteeCheckedInAt;
    return null;
  }

  /// The departure timestamp for [publicId], or null when they have not finished.
  DateTime? finishedAt(String publicId) {
    if (isTutor(publicId)) return tutorFinishedAt;
    if (isTutee(publicId)) return tuteeFinishedAt;
    return null;
  }

  /// Whether [publicId] has independently recorded their arrival.
  bool hasCheckedIn(String publicId) => checkedInAt(publicId) != null;

  /// Whether [publicId] has independently recorded their departure.
  bool hasFinished(String publicId) => finishedAt(publicId) != null;

  /// The meeting link the tutor shared, if any.
  ///
  /// Copyable rather than tappable on purpose: the app ships no link-opening
  /// dependency, and the agreed substitute for in-app chat is a value the student
  /// can hand to a browser.
  final String? meetingLink;
  final String? meetingVenue;
  final String? meetingVenueDetail;

  String? get venueLabel {
    final venue = meetingVenue;
    final detail = meetingVenueDetail;
    if (venue == null && detail == null) return null;
    if (venue == null) return detail;
    if (detail == null || detail.isEmpty) return venue;
    return '$venue · $detail';
  }

  /// Whether a rating exists for this session yet.
  ///
  /// A flag and not the rating. The session detail screen fetches the
  /// participant-scoped rating separately when the tutor needs to read feedback
  /// received for this session.
  final bool isRated;

  /// How many messages in this session's thread the reader has not opened.
  ///
  /// Counted by the server against the caller, not against the session: the same
  /// row is "two unread" for the student and "zero" for the tutor. Zero for a
  /// session whose thread nobody has written in, which is the ordinary case.
  final int unreadMessageCount;

  /// Whether there is something new in the thread worth pointing at.
  bool get hasUnreadMessages => unreadMessageCount > 0;

  final bool isOfflineSnapshot;

  final DateTime createdAt;

  /// Whether [publicId] is the student in this session.
  ///
  /// A comparison and not a stored role, because the API names both parties in
  /// every response and the client is one of them.
  bool isTutee(String publicId) => tuteeId == publicId;

  /// Whether [publicId] is the tutor in this session.
  bool isTutor(String publicId) => tutorId == publicId;

  /// The other party's public id, given who is asking.
  ///
  /// Null when [publicId] is neither party, which the API does not allow but
  /// which a stale cached profile could produce; the screens treat null as "say
  /// nothing" rather than naming the reader as the other party.
  String? otherPartyId(String publicId) {
    if (isTutee(publicId)) return tutorId;
    if (isTutor(publicId)) return tuteeId;
    return null;
  }

  /// The other party's name, given who is asking.
  ///
  /// Null for the same reason [otherPartyId] is, and also when the other account
  /// has never set a name. The screen falls back to the public id in that case,
  /// which is not a good answer but is an honest one -- an account with no name is
  /// better shown as itself than given a placeholder that reads like a person.
  String? otherPartyName(String publicId) {
    if (isTutee(publicId)) return tutorName;
    if (isTutor(publicId)) return tuteeName;
    return null;
  }

  /// The status as a student reads it.
  String get statusLabel => status?.label ?? statusWire;

  /// Whether the session is still ahead of the user.
  ///
  /// False for a status this client does not recognise: an unfamiliar state must
  /// not be presented as something to act on.
  bool get isActive => !isOfflineSnapshot && (status?.isActive ?? false);

  SessionModel copyWith({
    String? statusWire,
    TutoringSessionStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? tutorCheckedInAt,
    DateTime? tuteeCheckedInAt,
    DateTime? tutorFinishedAt,
    DateTime? tuteeFinishedAt,
    int? durationMinutes,
    String? meetingLink,
    String? meetingVenue,
    String? meetingVenueDetail,
    bool? isRated,
    int? unreadMessageCount,
  }) {
    return SessionModel(
      id: id,
      tuteeId: tuteeId,
      tutorId: tutorId,
      courseUnitId: courseUnitId,
      courseUnitCode: courseUnitCode,
      courseUnitName: courseUnitName,
      tuteeName: tuteeName,
      tutorName: tutorName,
      topic: topic,
      statusWire: statusWire ?? this.statusWire,
      status: status ?? this.status,
      helpRequestId: helpRequestId,
      scheduledStart: scheduledStart,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      tutorCheckedInAt: tutorCheckedInAt ?? this.tutorCheckedInAt,
      tuteeCheckedInAt: tuteeCheckedInAt ?? this.tuteeCheckedInAt,
      tutorFinishedAt: tutorFinishedAt ?? this.tutorFinishedAt,
      tuteeFinishedAt: tuteeFinishedAt ?? this.tuteeFinishedAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      meetingLink: meetingLink ?? this.meetingLink,
      meetingVenue: meetingVenue ?? this.meetingVenue,
      meetingVenueDetail: meetingVenueDetail ?? this.meetingVenueDetail,
      isRated: isRated ?? this.isRated,
      unreadMessageCount: unreadMessageCount ?? this.unreadMessageCount,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionModel &&
          other.id == id &&
          other.tuteeId == tuteeId &&
          other.tutorId == tutorId &&
          other.courseUnitId == courseUnitId &&
          other.topic == topic &&
          other.statusWire == statusWire &&
          other.helpRequestId == helpRequestId &&
          other.scheduledStart == scheduledStart &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt &&
          other.tutorCheckedInAt == tutorCheckedInAt &&
          other.tuteeCheckedInAt == tuteeCheckedInAt &&
          other.tutorFinishedAt == tutorFinishedAt &&
          other.tuteeFinishedAt == tuteeFinishedAt &&
          other.durationMinutes == durationMinutes &&
          other.meetingLink == meetingLink &&
          other.meetingVenue == meetingVenue &&
          other.meetingVenueDetail == meetingVenueDetail &&
          other.isRated == isRated &&
          other.unreadMessageCount == unreadMessageCount &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    tuteeId,
    tutorId,
    courseUnitId,
    topic,
    statusWire,
    helpRequestId,
    scheduledStart,
    startedAt,
    endedAt,
    // `Object.hash` takes at most twenty arguments. The second half is folded
    // into one hash rather than any field being dropped: two sessions that differ
    // only in who checked in must not be "equal" to a set.
    Object.hash(
      tutorCheckedInAt,
      tuteeCheckedInAt,
      tutorFinishedAt,
      tuteeFinishedAt,
      durationMinutes,
      meetingLink,
      meetingVenue,
      meetingVenueDetail,
      isRated,
      unreadMessageCount,
      createdAt,
    ),
  );

  @override
  String toString() => 'SessionModel($id, $topic, $statusWire)';
}

/// A public id, or null when the field is absent or not a string.
///
/// A non-string is treated as absent rather than coerced, on the same grounds as
/// an unrecognised status: a field that arrives as something else is a field this
/// client cannot use, and pretending otherwise would put a number in an id field.
String? _readId(Map<String, dynamic> json, String key) =>
    _readString(json, key);

String? _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return null;
}

/// A timestamp, or null when there is not one yet.
///
/// [DateTime.parse] throwing on a malformed value is deliberate and left to
/// propagate: an unparseable timestamp is a server fault, and the repository
/// reports it as one.
DateTime? _readDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return DateTime.parse(value as String);
}

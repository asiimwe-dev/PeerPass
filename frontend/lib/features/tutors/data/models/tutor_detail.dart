import 'package:flutter/foundation.dart';
import 'package:peerpass/core/models/tutor_summary.dart';
import 'package:peerpass/features/tutors/data/models/tutor_rail_entry.dart';

/// One tutor's profile as the detail screen shows it.
///
/// `profile` is kept as the nested object rather than flattened onto this type,
/// because the API nests it: `TutorDetailResponse` wraps `TutorProfileSummary`
/// on purpose, so that the policy deciding what a student may see about a tutor
/// lives in one schema instead of being restated in five fields here.
@immutable
class TutorDetail {
  const TutorDetail({
    required this.profile,
    required this.endorsedCourseUnitIds,
    required this.endorsementCount,
  });

  /// Reads the detail response.
  ///
  /// A response with no `profile` object is a [FormatException] rather than a
  /// detail screen with a name on it and nothing else: there is no neutral
  /// reading of a missing profile, and the repository turns this into a
  /// message a student can act on.
  factory TutorDetail.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'];
    if (profile is! Map<String, dynamic>) {
      throw const FormatException('tutor detail response carried no profile');
    }

    final count = json['endorsement_count'];
    if (count is! num) {
      throw const FormatException('tutor detail carried no endorsement count');
    }

    return TutorDetail(
      profile: TutorSummary.fromJson(profile),
      endorsedCourseUnitIds: readIdList(json['endorsed_course_unit_ids']),
      endorsementCount: count.toInt(),
    );
  }

  final TutorSummary profile;

  /// The endorsed units, capped by the API in the same way the rail's are.
  ///
  /// Ids, not names: nothing in this response says what the units are called,
  /// and the client resolves them against the course-unit catalogue rather than
  /// rendering an id and calling it a unit.
  final List<String> endorsedCourseUnitIds;

  /// The true total, which can exceed the number of ids above.
  final int endorsementCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorDetail &&
          other.profile == profile &&
          other.endorsementCount == endorsementCount &&
          listEquals(other.endorsedCourseUnitIds, endorsedCourseUnitIds);

  @override
  int get hashCode => Object.hash(
    profile,
    endorsementCount,
    Object.hashAll(endorsedCourseUnitIds),
  );

  @override
  String toString() => 'TutorDetail(${profile.userId}, $endorsementCount)';
}

import 'package:flutter/foundation.dart';
import 'package:peerpass/core/models/tutor_summary.dart';

/// One tutor as the browse rail shows them.
///
/// Flat on the wire and nested here. `TutorRailEntry` is the whole student-facing
/// tutor shape plus the two endorsement fields, so the five shared fields are
/// read by handing the same map to [TutorSummary.fromJson] rather than by
/// unpacking it a second time. Nothing is invented: the map carries exactly the
/// keys `TutorProfileSummary` reads.
@immutable
class TutorRailEntry {
  const TutorRailEntry({
    required this.tutor,
    required this.endorsedCourseUnitIds,
    required this.endorsementCount,
  });

  /// Reads one rail entry.
  ///
  /// `endorsed_course_unit_ids` defaults to empty because an absent list and an
  /// empty one mean the same thing here -- no endorsement -- and the API
  /// documents that as a real state rather than a fault. `endorsement_count`
  /// does *not* default: the number beside a capped sample of five units is the
  /// one figure on the card that is the whole truth, and reading a missing one
  /// as zero would turn a server fault into a claim that nobody endorsed
  /// anybody.
  factory TutorRailEntry.fromJson(Map<String, dynamic> json) {
    final count = json['endorsement_count'];
    if (count is! num) {
      throw const FormatException('rail entry carried no endorsement count');
    }

    return TutorRailEntry(
      tutor: TutorSummary.fromJson(json),
      endorsedCourseUnitIds: readIdList(json['endorsed_course_unit_ids']),
      endorsementCount: count.toInt(),
    );
  }

  final TutorSummary tutor;

  /// The units this tutor has been endorsed for, capped by the API.
  ///
  /// A sample, not the whole set: the API sends at most five while
  /// [endorsementCount] carries the total. A card that laid out every endorsed
  /// unit would be a list, not a rail.
  final List<String> endorsedCourseUnitIds;

  /// How many endorsements the tutor has in total, across every unit.
  final int endorsementCount;

  /// How many endorsements, as a student reads it.
  ///
  /// One is "Endorsed once" rather than "1 endorsement", and zero says so
  /// plainly: a tutor with no endorsements is not a tutor with a rating of zero,
  /// and the difference is the whole reason the count is a separate field.
  String get endorsementLabel {
    if (endorsementCount <= 0) return 'No endorsements yet';
    if (endorsementCount == 1) return 'Endorsed once';
    return 'Endorsed $endorsementCount times';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorRailEntry &&
          other.tutor == tutor &&
          other.endorsementCount == endorsementCount &&
          listEquals(other.endorsedCourseUnitIds, endorsedCourseUnitIds);

  @override
  int get hashCode => Object.hash(
    tutor,
    endorsementCount,
    Object.hashAll(endorsedCourseUnitIds),
  );

  @override
  String toString() => 'TutorRailEntry(${tutor.userId}, $endorsementCount)';
}

/// The public ids in a list field, dropping anything that is not a string.
///
/// A non-string entry is dropped rather than coerced, which is the same
/// tolerance the rest of the client applies to an id field: a value this client
/// cannot use is one it must not display. A whole list of them leaves an empty
/// sample next to the real count, which is honest -- the count is what the card
/// trusts.
List<String> readIdList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is String && entry.isNotEmpty) entry,
  ];
}

import 'package:flutter/foundation.dart';

/// A degree programme a faculty publishes, as the reference endpoint returns it.
///
/// Programmes are the shelf a catalogue is organised by: a student on the
/// Information Technology programme is offered that programme's course units and
/// the faculty-wide ones, not a sibling programme's. The faculty is still part of
/// the record because the endpoint can be asked for one faculty's programmes.
@immutable
class ProgramOption {
  const ProgramOption({
    required this.publicId,
    required this.name,
    required this.facultyId,
  });

  factory ProgramOption.fromJson(Map<String, dynamic> json) => ProgramOption(
    publicId: json['id'] as String,
    name: json['name'] as String,
    facultyId: json['faculty_id'] as String,
  );

  final String publicId;

  final String name;

  /// The faculty that offers this programme, as a public id.
  ///
  /// Carried rather than inferred so the picker can be keyed on the faculty it
  /// was asked for, and so a test fixture can hand back a believable catalogue
  /// without a second lookup.
  final String facultyId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgramOption &&
          other.publicId == publicId &&
          other.name == name &&
          other.facultyId == facultyId;

  @override
  int get hashCode => Object.hash(publicId, name, facultyId);

  @override
  String toString() => 'ProgramOption($name)';
}

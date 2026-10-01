import 'package:peerpass/core/models/subject.dart';
import 'package:peerpass/features/auth/data/models/university_option.dart';

const mustFallbackUniversityId = 'fallback:must';

const mustFallbackUniversityName =
    'Mbarara University of Science and Technology';

const _facultyPrefix = 'fallback:must:faculty:';

const mustFallbackUniversity = UniversityOption(
  publicId: mustFallbackUniversityId,
  name: mustFallbackUniversityName,
  isFallback: true,
);

const mustFallbackFaculties = <Subject>[
  Subject(publicId: '${_facultyPrefix}medicine', name: 'Faculty of Medicine'),
  Subject(publicId: '${_facultyPrefix}science', name: 'Faculty of Science'),
  Subject(
    publicId: '${_facultyPrefix}computing',
    name: 'Faculty of Computing and Informatics Sciences',
  ),
  Subject(
    publicId: '${_facultyPrefix}applied',
    name: 'Faculty of Applied Sciences and Technology',
  ),
  Subject(
    publicId: '${_facultyPrefix}interdisciplinary',
    name: 'Faculty of Interdisciplinary Studies',
  ),
  Subject(
    publicId: '${_facultyPrefix}business',
    name: 'Faculty of Business and Management Sciences',
  ),
];

bool isMustFallbackUniversity(String? id) => id == mustFallbackUniversityId;

String? mustFallbackFacultyName(String? id) {
  for (final faculty in mustFallbackFaculties) {
    if (faculty.publicId == id) return faculty.name;
  }
  return null;
}

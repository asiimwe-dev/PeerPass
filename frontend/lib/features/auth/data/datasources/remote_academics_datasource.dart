import 'dart:async';

import 'package:dio/dio.dart';
import 'package:peerpass/core/models/course_unit_option.dart';
import 'package:peerpass/core/models/grade_option.dart';
import 'package:peerpass/core/models/subject.dart';
import 'package:peerpass/core/models/university_option.dart';
import 'package:peerpass/core/storage/session_cache.dart';

/// Reads the reference data the onboarding wizard offers.
///
/// Unauthenticated on purpose. Sign-up asks a stranger where they study, before
/// there is anything to authenticate as, so requiring a token here would leave
/// the first screen of the app unreachable.
class RemoteAcademicsDatasource {
  const RemoteAcademicsDatasource(this._dio, {this.cache});

  final Dio _dio;
  final SessionCache? cache;

  /// The university catalogue, from the last sync when there is one.
  ///
  /// Reference data changes rarely, and it is read on screens that must appear
  /// immediately -- the profile's University row among them. Returning the saved
  /// copy first and refreshing it behind the screen is the difference between a
  /// name and a ten-second "Loading…" on a cold start with no connection. The
  /// next read (or next launch) sees the refreshed copy.
  Future<List<UniversityOption>> universities() async {
    final cached = await cache?.readUniversities();
    if (cached != null) {
      _refreshInBackground(_refreshUniversities);
      return [for (final row in cached) UniversityOption.fromJson(row)];
    }
    return await _refreshUniversities();
  }

  /// Lets the saved copy stand when the refresh fails.
  ///
  /// A background refresh has no caller to hand an error to, and an unhandled
  /// one would be an error report with no user-visible failure behind it. The
  /// cached answer is still a correct answer to "what was the catalogue"; the
  /// next foreground read will try again.
  void _refreshInBackground(Future<Object?> Function() refresh) {
    unawaited(() async {
      try {
        await refresh();
      } on Object {
        // The saved copy is still being served.
      }
    }());
  }

  Future<List<UniversityOption>> _refreshUniversities() async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/academics/universities',
    );
    final universities = [
      for (final row in response.data!)
        UniversityOption.fromJson(row as Map<String, dynamic>),
    ];
    await cache?.writeUniversities([
      for (final university in universities)
        {
          'id': university.publicId,
          'name': university.name,
          'grading_scale_id': university.gradingScaleId,
        },
    ]);
    return universities;
  }

  /// The faculties, in alphabetical order.
  ///
  /// The API models a faculty as a `Subject`, because that is what groups course
  /// units, and the wizard offers the units in the faculty a student picked. The
  /// client does not rename it: calling the same rows "subjects" here would mean
  /// the wizard and the API disagree about the word for the same thing.
  ///
  /// Not filtered by university, because the API does not filter it. A faculty is
  /// a property of a course unit rather than of an institution, so the list is
  /// global while the pilot is a single institution.
  Future<List<Subject>> faculties({required String universityId}) async {
    final cached = await cache?.readFaculties(universityId);
    if (cached != null) {
      _refreshInBackground(() => _refreshFaculties(universityId));
      return [
        for (final row in cached)
          Subject(publicId: row['id'] as String, name: row['name'] as String),
      ];
    }
    return await _refreshFaculties(universityId);
  }

  Future<List<Subject>> _refreshFaculties(String universityId) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/academics/faculties',
      queryParameters: {'university_id': universityId},
    );
    final faculties = [
      for (final row in response.data!)
        Subject(
          publicId: (row as Map<String, dynamic>)['id'] as String,
          name: row['name'] as String,
        ),
    ];
    await cache?.writeFaculties(universityId, [
      for (final faculty in faculties)
        {'id': faculty.publicId, 'name': faculty.name},
    ]);
    return faculties;
  }

  /// Course units for the given university, for the primary modules step.
  ///
  /// Filtered by university so a student only sees units from their own
  /// institution. The API accepts an optional `university_id` query param.
  Future<List<CourseUnitOption>> courseUnits({
    String? universityId,
    String? subjectId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/academics/course-units',
      queryParameters: {
        'university_id': ?universityId,
        'subject_id': ?subjectId,
      },
    );
    return [
      for (final row in response.data!)
        CourseUnitOption.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// Grades for the selected university's published scale.
  Future<List<GradeOption>> grades({String? universityId}) async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/academics/grades',
      queryParameters: {'university_id': universityId},
    );
    return [
      for (final row in response.data!)
        GradeOption.fromJson(row as Map<String, dynamic>),
    ];
  }
}

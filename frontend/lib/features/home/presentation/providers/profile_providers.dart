import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/models/program_option.dart';
import 'package:peerpass/core/models/subject.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';

/// Resolves the profile's stored university identifier to its display record.
///
/// The profile API intentionally stores only the public identifier. Keeping the
/// lookup here means the Profile screen never has to know the wire shape or
/// display an internal ID when reference data is unavailable.
// ignore: specify_nonobvious_property_types
final universityByIdProvider = FutureProvider.family<String?, String>((
  ref,
  universityId,
) {
  if (universityId.isEmpty) return null;

  return ref.read(authRepositoryProvider).universityNameById(universityId);
});

/// The faculties a university publishes, for the profile's faculty picker.
///
/// Named for the university rather than the current profile because the answer
/// belongs to the catalogue and is the same whichever student asks.
// The family parameter's type is inferred from the family declaration, which is
// the same reason [universityByIdProvider] needs one.
// ignore: specify_nonobvious_property_types
final facultiesForUniversityProvider =
    FutureProvider.family<List<Subject>, String>((ref, universityId) {
      if (universityId.isEmpty) return const <Subject>[];

      return ref
          .read(authRepositoryProvider)
          .faculties(universityId: universityId);
    });

/// The programmes a faculty publishes, for the profile's programme picker.
///
/// Read through the auth repository rather than the onboarding picker's
/// provider: `home/` may depend on another feature's data contract, never its
/// presentation layer. The answer belongs to the catalogue and is the same
/// whichever student asks.
// The family parameter's type is inferred from the family declaration.
// ignore: specify_nonobvious_property_types
final programsForFacultyProvider =
    FutureProvider.family<
      List<ProgramOption>,
      ({String universityId, String facultyId})
    >(
      (ref, scope) => ref
          .read(authRepositoryProvider)
          .programs(
            universityId: scope.universityId,
            facultyId: scope.facultyId,
          ),
    );

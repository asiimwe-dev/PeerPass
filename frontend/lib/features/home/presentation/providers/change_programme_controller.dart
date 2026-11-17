import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';

/// Moves the signed-in account to another programme inside its faculty.
///
/// A programme is a shelf of the catalogue the student already owns, which is
/// why this is a profile edit while the faculty above it is not. The API checks
/// the programme belongs to the account's own faculty and prunes the declared
/// modules the new shelf does not publish, so the record it returns is adopted
/// whole rather than patched locally: the pruned unit list and the programme name
/// are both things only the server knows.
///
/// The session is the source of truth every catalogue provider keys on, so
/// adopting the returned record is also what makes the screens re-read the new
/// shelf without a manual refresh.
final changeProgrammeControllerProvider = Provider<Future<void> Function(String)>(
  (ref) {
    return (programmeId) async {
      final profile = await ref
          .read(authRepositoryProvider)
          .updateProfile(programId: programmeId);
      ref.read(sessionControllerProvider.notifier).signedIn(profile);
    };
  },
);

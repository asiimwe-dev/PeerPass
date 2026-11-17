import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/offline_notice.dart';
import 'package:peerpass/features/competencies/data/repositories/competencies_repository.dart';
import 'package:peerpass/features/home/presentation/providers/change_programme_controller.dart';
import 'package:peerpass/features/home/presentation/providers/profile_providers.dart';
import 'package:peerpass/features/home/presentation/providers/sign_out_controller.dart';
import 'package:peerpass/features/home/presentation/widgets/delete_account_tile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final profile = session.profile;
    final theme = Theme.of(context);
    final university = profile?.universityId == null
        ? null
        : ref.watch(universityByIdProvider(profile!.universityId!));
    final applications = ref.watch(myClaimsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.xl),
          children: [
            CircleAvatar(radius: 32, child: Text(profile?.initials ?? '?')),
            const SizedBox(height: AppDimens.md),
            Text(
              profile?.fullName ?? 'PeerPass student',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.xs),
            Text(
              profile?.email ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.xl),
            if (session.isOffline) ...[
              const OfflineNotice(
                message: 'No connection · showing your saved profile',
              ),
              const SizedBox(height: AppDimens.lg),
            ],
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('University'),
                    subtitle: university == null
                        ? const Text('Not provided')
                        : university.when(
                            data: (value) => Text(value ?? 'Unavailable'),
                            loading: () => const Text('Loading...'),
                            error: (_, _) => const Text('Unavailable'),
                          ),
                  ),
                  _FacultyTile(profile: profile),
                  _ProgrammeTile(profile: profile),
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Role'),
                    subtitle: Text(_roleLabel(profile)),
                  ),
                  if (applications.value?.isNotEmpty ?? false)
                    ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: const Text('Tutor applications'),
                      subtitle: const Text('Where your submitted proofs stand'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.myApplications),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.lg),
            FilledButton.icon(
              onPressed: () => ref.read(signOutControllerProvider)(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: AppDimens.lg),
            const DeleteAccountTile(),
          ],
        ),
      ),
    );
  }

  String _roleLabel(UserProfile? profile) {
    if (profile?.hasRole(UserRole.tutor) ?? false) {
      return 'Student and tutor';
    }
    return 'Student';
  }
}

/// The student's faculty, shown but not editable.
///
/// The faculty is the scope of everything academic: the course catalogue, the
/// tutor rail, the modules a student declares and every competency a tutor
/// claims. A change is therefore not a profile correction but a move to another
/// catalogue, and it is an operator action rather than a switch a student can
/// flip while browsing. The row is read-only and says so by offering no control.
class _FacultyTile extends ConsumerWidget {
  const _FacultyTile({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final universityId = profile?.universityId;
    final facultyId = profile?.facultyId;

    // Faculties belong to a university, and the name is resolved from the same
    // public list the onboarding picker uses. With nothing chosen there is
    // nothing to resolve, and the row says what is missing.
    if (universityId == null || facultyId == null) {
      return const ListTile(
        leading: Icon(Icons.account_balance_outlined),
        title: Text('Faculty'),
        subtitle: Text('Not provided'),
      );
    }

    final faculties = ref.watch(facultiesForUniversityProvider(universityId));

    return ListTile(
      leading: const Icon(Icons.account_balance_outlined),
      title: const Text('Faculty'),
      subtitle: faculties.when(
        data: (values) {
          for (final faculty in values) {
            if (faculty.publicId == facultyId) return Text(faculty.name);
          }
          // An id the catalogue no longer lists is a server-side change, not a
          // state a student can fix; naming it is more honest than a spinner.
          return const Text('Unavailable');
        },
        loading: () => const Text('Loading...'),
        error: (_, _) => const Text('Unavailable'),
      ),
    );
  }
}

/// The student's programme, and the control that changes it.
///
/// Editable, unlike the faculty above it: every programme belongs to the
/// faculty the account already sits in, so the move stays inside one catalogue
/// and the server prunes only the declared units the new shelf no longer
/// publishes. The row still offers a catalogue rather than free text -- a
/// programme is a record other endpoints act on, not a label.
///
/// A faculty that publishes none is a normal state, not a broken picker: the row
/// says the student sees the whole faculty catalogue and offers no control,
/// because there is nothing to choose.
class _ProgrammeTile extends ConsumerWidget {
  const _ProgrammeTile({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final universityId = profile?.universityId;
    final facultyId = profile?.facultyId;

    if (universityId == null || facultyId == null) {
      return const ListTile(
        leading: Icon(Icons.workspaces_outline),
        title: Text('Programme'),
        subtitle: Text('Not provided'),
      );
    }

    final programmes = ref.watch(
      programsForFacultyProvider((
        universityId: universityId,
        facultyId: facultyId,
      )),
    );

    // The name travels with the profile, so the row can label the current choice
    // before the catalogue arrives. An id without a name is a server-side
    // mismatch, not a missing choice.
    final current =
        profile?.programName ??
        (profile?.programId == null ? null : 'Unavailable');

    return programmes.when(
      loading: () => ListTile(
        leading: const Icon(Icons.workspaces_outline),
        title: const Text('Programme'),
        subtitle: Text(current ?? 'Loading...'),
      ),
      error: (_, _) => ListTile(
        leading: const Icon(Icons.workspaces_outline),
        title: const Text('Programme'),
        subtitle: Text(current ?? 'Unavailable'),
      ),
      data: (values) => values.isEmpty
          ? const ListTile(
              leading: Icon(Icons.workspaces_outline),
              title: Text('Programme'),
              subtitle: Text('Whole faculty'),
            )
          : ListTile(
              leading: const Icon(Icons.workspaces_outline),
              title: const Text('Programme'),
              subtitle: Text(current ?? 'Not selected'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _chooseProgramme(context, ref),
            ),
    );
  }

  Future<void> _chooseProgramme(BuildContext context, WidgetRef ref) async {
    final universityId = profile?.universityId;
    final facultyId = profile?.facultyId;
    if (universityId == null || facultyId == null) return;
    final current = profile?.programId;

    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ProgrammeSheet(
        universityId: universityId,
        facultyId: facultyId,
        currentProgrammeId: current,
      ),
    );
    if (chosen == null || chosen == current || !context.mounted) return;

    final before = ref.read(sessionControllerProvider).profile;
    try {
      await ref.read(changeProgrammeControllerProvider)(chosen);
      if (!context.mounted) return;
      final after = ref.read(sessionControllerProvider).profile;
      // Only mentioned when it happened: a programme change usually keeps most
      // of the student's units, and an unconditional warning would read as a
      // loss that did not occur.
      final pruned =
          (before?.primaryCourseUnitIds.length ?? 0) -
          (after?.primaryCourseUnitIds.length ?? 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pruned > 0
                ? 'Programme updated. Course units outside it were removed.'
                : 'Programme updated.',
          ),
        ),
      );
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change programme. Try again.')),
      );
    }
  }
}

/// The programmes the account's faculty publishes, with the current one marked.
class _ProgrammeSheet extends ConsumerWidget {
  const _ProgrammeSheet({
    required this.universityId,
    required this.facultyId,
    required this.currentProgrammeId,
  });

  final String universityId;
  final String facultyId;
  final String? currentProgrammeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = (universityId: universityId, facultyId: facultyId);
    final programmes = ref.watch(programsForFacultyProvider(scope));

    return SafeArea(
      child: programmes.when(
        loading: () => const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => FailureView(
          failure: error is Failure ? error : const UnknownFailure(),
          onRetry: () => ref.invalidate(programsForFacultyProvider(scope)),
        ),
        data: (values) => values.isEmpty
            ? const EmptyView(
                icon: Icons.workspaces_outline,
                title: 'No programmes yet',
                message:
                    'This faculty has not published its programmes yet, so '
                    'there is nothing to choose. You still see the whole '
                    'faculty catalogue.',
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.xl,
                      0,
                      AppDimens.xl,
                      AppDimens.sm,
                    ),
                    child: Text(
                      'Your programme decides which course units you can ask '
                      'for help with.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final programme in values)
                    ListTile(
                      title: Text(
                        programme.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: programme.publicId == currentProgrammeId
                          ? const Icon(Icons.check)
                          : null,
                      selected: programme.publicId == currentProgrammeId,
                      onTap: () =>
                          Navigator.of(context).pop(programme.publicId),
                    ),
                ],
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/widgets/offline_notice.dart';
import 'package:peerpass/features/competencies/data/repositories/competencies_repository.dart';
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

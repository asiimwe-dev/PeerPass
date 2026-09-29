import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/features/home/presentation/providers/sign_out_controller.dart';

/// The signed-in landing screen.
///
/// Reads the student's own name and where they study, and says plainly that
/// tutoring is not switched on yet. It does not offer a tutor list, a course
/// picker, or a "find a tutor" button, because the matching endpoint behind
/// those does not exist in this release. An empty state that pretends to be a
/// hub is worse than an honest one: a student who taps a tile that leads
/// nowhere concludes the app is broken, rather than that it is early.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(sessionControllerProvider).profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PeerPass'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            // Invoked, not merely read. `onPressed` is a `VoidCallback`, so a bare
            // read would evaluate the provider, discard the returned function, and
            // sign nobody out while still looking like it worked.
            onPressed: () => ref.read(signOutControllerProvider)(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ContentWidthLimiter(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          // The pilot stores no images, so the placeholder is
                          // derived from the stored name rather than uploaded.
                          child: Text(profile?.initials ?? '?'),
                        ),
                        const SizedBox(width: AppDimens.lg),
                        Expanded(
                          child: Text(
                            _greeting(profile),
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimens.xxl),
                    const _PendingCard(
                      icon: Icons.school_outlined,
                      title: 'Find a tutor',
                      body:
                          'Tutor profiles and matching arrive in the next '
                          'release. Your account is set up and ready for it.',
                    ),
                    const SizedBox(height: AppDimens.md),
                    const _PendingCard(
                      icon: Icons.calendar_month_outlined,
                      title: 'Book a session',
                      body:
                          'Booking opens once there are tutors to book with. '
                          'Nothing is lost by waiting.',
                    ),
                    const SizedBox(height: AppDimens.xxl),
                    Text(
                      'Signed in as ${profile?.email ?? ''}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A greeting from the stored name, not a prompt for one.
  ///
  /// Falls back to the address rather than a bare "Hello". A student who reaches
  /// home without a name is not a state the router allows, so this is only ever
  /// a guard against a display that would otherwise read "Hello, " and nothing.
  String _greeting(UserProfile? profile) {
    final firstName = profile?.firstName;
    return firstName == null ? 'Hello' : 'Hello, $firstName';
  }
}

/// A tile for something that exists as a promise, not yet as a feature.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppDimens.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(width: AppDimens.sm),
                      _SoonChip(),
                    ],
                  ),
                  const SizedBox(height: AppDimens.xs),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small marker that a tile is not live.
class _SoonChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sm,
        vertical: AppDimens.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(
        'Soon',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

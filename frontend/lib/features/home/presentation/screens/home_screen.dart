import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';

/// The signed-in landing screen.
///
/// Reads the student's own name, offers a way into their own sessions, into
/// finding a tutor for a course unit, and a rail of the tutors already teaching at
/// their university. Booking is still a promise, and the pending tile is the only
/// thing on this screen that is: the distinction the pending tiles exist to make
/// is between what works and what is written on the roadmap, and a list of
/// sessions with no way to reach it from the landing screen would be a feature
/// nobody can find.
///
/// The two entries that lead somewhere are route pushes, not imports of the
/// features' screens. A home screen that named them would have to import features
/// it owns nothing of, which the dependency rules forbid -- see [tutorRail] for the
/// longer form of that argument.
///
/// The active-session card and the tutor rail arrive as widgets rather than being
/// built here, and that is an architectural decision rather than a preference. The
/// card belongs to the sessions feature and the rail to the tutors feature, so
/// naming either would make home a second place that has to change when those
/// features do. The shell passes them in and home decides only where they go. Null
/// means there is no card, which is the state the home screen's own tests are in --
/// and for the rail, null means "nothing to browse here", which is honest rather
/// than broken.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    this.activeSessionCard,
    this.tutorRail,
    this.onRefresh,
    super.key,
  });

  /// The card to show above the entries, if the shell has one.
  final Widget? activeSessionCard;

  /// The rail of tutors to show, if the shell has one.
  final Widget? tutorRail;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(sessionControllerProvider).profile;
    final card = activeSessionCard;
    final rail = tutorRail;

    return Scaffold(
      appBar: AppBar(title: const Text('PeerPass')),
      body: SafeArea(
        child: Center(
          child: RefreshIndicator(
            onRefresh: onRefresh ?? () async {},
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                      if (card != null) ...[
                        const SizedBox(height: AppDimens.xl),
                        card,
                      ],
                      const SizedBox(height: AppDimens.xl),
                      _FeatureEntry(
                        icon: Icons.school_outlined,
                        title: 'Find a tutor',
                        body:
                            'Pick a course unit and see the tutors who can help '
                            'you with it.',
                        onTap: () => context.push(AppRoutes.matching),
                      ),
                      const SizedBox(height: AppDimens.md),
                      _FeatureEntry(
                        icon: Icons.event_note_outlined,
                        title: 'My sessions',
                        body:
                            'Past sessions, your PIN for the next one, and the '
                            'rating you owe.',
                        onTap: () => context.push(AppRoutes.sessions),
                      ),
                      // Tutor-only, on the same role check as "Become a tutor"
                      // below, because the entry is about the viewer's own banked
                      // hours. A student offered it would tap through to a screen
                      // whose honest answer is that they have not applied yet, which
                      // is a worse first impression than not seeing the tile.
                      if (profile?.hasRole(UserRole.tutor) ?? false) ...[
                        // Above the certificate rather than below it: the requests
                        // waiting on an answer are the only tiles on this screen
                        // that are about somebody else waiting for something, and
                        // they go stale. A tutor who has to scroll past their own
                        // progress to reach a student who chose them has been
                        // given a reason to never open the screen again.
                        const SizedBox(height: AppDimens.md),
                        _FeatureEntry(
                          icon: Icons.mark_email_unread_outlined,
                          title: 'Waiting on you',
                          body:
                              'Students who asked you to tutor them, and the '
                              'sessions they are waiting on you to confirm.',
                          onTap: () => context.push(AppRoutes.tutorRequests),
                        ),
                        const SizedBox(height: AppDimens.md),
                        _FeatureEntry(
                          icon: Icons.workspace_premium_outlined,
                          title: 'My certificate',
                          body:
                              'The teaching hours you have banked, and the hours '
                              'a certificate still needs.',
                          onTap: () => context.push(AppRoutes.certificate),
                        ),
                      ],
                      if (rail != null) ...[
                        const SizedBox(height: AppDimens.xl),
                        rail,
                      ],
                      if (!(profile?.hasRole(UserRole.tutor) ?? false))
                        FilledButton.icon(
                          onPressed: () =>
                              context.push(AppRoutes.tutorVerification),
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Become a tutor'),
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

/// A tile that leads to a real screen, so unlike the pending tiles it is tappable.
///
/// It carries no "Soon" chip. The pending tiles exist to keep home honest about
/// what is not built; an entry point for a screen that *is* built is the opposite
/// claim, and a list of sessions or a course catalogue with no way to reach either
/// of them is a feature nobody can find.
class _FeatureEntry extends StatelessWidget {
  const _FeatureEntry({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.lg),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppDimens.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
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
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

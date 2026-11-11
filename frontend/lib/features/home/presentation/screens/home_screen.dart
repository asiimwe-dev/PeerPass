import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_palette.dart';
import 'package:peerpass/core/widgets/app_avatar.dart';
import 'package:peerpass/core/widgets/app_button.dart';
import 'package:peerpass/core/widgets/app_card.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/section_header.dart';

/// The signed-in landing screen.
///
/// A composer, not a feature directory. The student arrives with a problem and
/// the screen's job is to get them from that problem to a person: the course is
/// one chip, the question is one field, and the action is one button. Sessions
/// and the account live in the bottom bar, so repeating them here as tiles would
/// be a menu dressed up as a dashboard.
///
/// The composer, the active-session card, and the tutor rail arrive as widgets
/// rather than being built here, and that is an architectural decision rather
/// than a preference. Each belongs to a feature that owns its data, so naming
/// any of them would make home a second place that has to change when those
/// features do. The shell passes them in and home decides only where they go.
/// Null means the screen is being pumped on its own, which is the state home's
/// own tests are in.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    this.askComposer,
    this.activeSessionCard,
    this.tutorRail,
    this.onRefresh,
    super.key,
  });

  /// The composer the matching feature builds. Null falls back to a plain button
  /// into the catalogue, so home is never a dead end.
  final Widget? askComposer;

  /// The card to show above the entries, if the shell has one.
  final Widget? activeSessionCard;

  /// The rail of tutors to show, if the shell has one.
  final Widget? tutorRail;

  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final profile = ref.watch(sessionControllerProvider).profile;
    final composer = askComposer;
    final card = activeSessionCard;
    final rail = tutorRail;
    final isTutor = profile?.hasRole(UserRole.tutor) ?? false;

    final content = SingleChildScrollView(
      physics: onRefresh == null
          ? const ClampingScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      child: ContentWidthLimiter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.screenPadding,
            AppDimens.lg,
            AppDimens.screenPadding,
            AppDimens.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppAvatar(name: profile?.fullName ?? '?'),
                  const SizedBox(width: AppDimens.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(profile),
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppDimens.xxs),
                        Text(
                          "Let's get you unstuck.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.xl),
              if (composer != null)
                composer
              else
                AppButton(
                  label: 'Find a tutor',
                  onPressed: () => context.push(AppRoutes.matching),
                ),
              if (card != null) ...[const SizedBox(height: AppDimens.xl), card],
              if (rail != null) ...[
                const SizedBox(height: AppDimens.xxl),
                rail,
              ],
              if (isTutor) ...[
                const SizedBox(height: AppDimens.xxl),
                const SectionHeader(
                  title: 'For tutors',
                  subtitle: 'Requests, hours, and the certificate they earn.',
                ),
                const SizedBox(height: AppDimens.md),
                // The dashboard first, then the two shortcuts it summarises.
                // A tutor who is looking for "what needs me now" should not
                // have to choose between three entries to find it; the direct
                // links stay because a tutor who already knows where they are
                // going should not have to pass through the dashboard.
                _HomeEntry(
                  icon: Icons.space_dashboard_outlined,
                  title: 'Your tutor HQ',
                  subtitle: 'Progress, requests, and availability',
                  onTap: () => context.push(AppRoutes.tutorHq),
                ),
                const SizedBox(height: AppDimens.sm),
                _HomeEntry(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'Waiting on you',
                  onTap: () => context.push(AppRoutes.tutorRequests),
                ),
                const SizedBox(height: AppDimens.sm),
                // A tutor can teach more than one course. The entry stays here
                // after the first approval, where the verification flow used to
                // disappear entirely, and it leads to the status screen so a
                // tutor can see the cap and apply from the same place.
                _HomeEntry(
                  icon: Icons.fact_check_outlined,
                  title: 'Course applications',
                  subtitle: 'Your courses, and applying for another',
                  onTap: () => context.push(AppRoutes.myApplications),
                ),
                const SizedBox(height: AppDimens.sm),
                _HomeEntry(
                  icon: Icons.workspace_premium_outlined,
                  title: 'My certificate',
                  onTap: () => context.push(AppRoutes.certificate),
                ),
              ] else ...[
                const SizedBox(height: AppDimens.xxl),
                AppButton(
                  label: 'Become a tutor',
                  variant: AppButtonVariant.ghost,
                  icon: Icons.verified_user_outlined,
                  onPressed: () => context.push(AppRoutes.tutorVerification),
                ),
              ],
              const SizedBox(height: AppDimens.xl),
              Text(
                'Signed in as ${profile?.email ?? ''}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: onRefresh == null
              ? content
              : RefreshIndicator(onRefresh: () => onRefresh!(), child: content),
        ),
      ),
    );
  }

  /// A greeting from the stored name, not a prompt for one.
  ///
  /// Falls back to "there" rather than a bare "Hey". A student who reaches home
  /// without a name is not a state the router allows, so this is only ever a
  /// guard against a heading that would otherwise read "Hey ,".
  String _greeting(UserProfile? profile) {
    final firstName = profile?.firstName;
    return firstName == null ? 'Hey there 👋' : 'Hey $firstName 👋';
  }
}

/// One quiet entry, used for the two things a tutor can do from home.
///
/// A card rather than a list tile so it carries the same lift as the rest of the
/// screen; a row rather than a paragraph because these are secondary to the
/// composer and should not compete with it.
class _HomeEntry extends StatelessWidget {
  const _HomeEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppDimens.lg),
      semanticLabel: title,
      child: Row(
        children: [
          Icon(icon, color: palette.primary, size: 22),
          const SizedBox(width: AppDimens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle case final text?) ...[
                  const SizedBox(height: AppDimens.xxs),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.muted),
        ],
      ),
    );
  }
}

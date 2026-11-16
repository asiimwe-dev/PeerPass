import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';
import 'package:peerpass/features/sessions/presentation/screens/sessions_list_screen.dart';

/// The Sessions tab: tutor entry points above the list of every session.
///
/// Stateful only to re-read the list on entry. `sessionListProvider` is
/// keep-alive, so returning to this tab re-runs `build` but not the fetch: a
/// thread read from the bell, or a session another party just finished, would
/// stay stale on the one screen built to show them. Opening the tab is the
/// moment a student expects it to be current, and the pull-to-refresh inside the
/// list is still there for a deliberate re-read.
class SessionsTabScreen extends ConsumerStatefulWidget {
  const SessionsTabScreen({super.key});

  @override
  ConsumerState<SessionsTabScreen> createState() => _SessionsTabScreenState();
}

class _SessionsTabScreenState extends ConsumerState<SessionsTabScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so this cannot race the provider's own first load.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Nothing loaded yet means the provider's first load (or its failure, which
      // the list screen offers a retry for) is still the answer.
      if (ref.read(sessionListProvider).value == null) return;
      ref.invalidate(sessionListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTutor =
        ref.watch(sessionControllerProvider).profile?.hasRole(UserRole.tutor) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: Column(
        children: [
          if (isTutor)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.lg,
                AppDimens.md,
                AppDimens.lg,
                0,
              ),
              child: Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.insights_outlined),
                      title: Text('Tutor insights'),
                      subtitle: Text(
                        'Review requests and track your teaching certificate.',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.inbox_outlined),
                      title: const Text('Requests'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.tutorRequests),
                    ),
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: const Text('Certificate progress'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.certificate),
                    ),
                  ],
                ),
              ),
            ),
          const Expanded(child: SessionsListScreen(showAppBar: false)),
        ],
      ),
    );
  }
}

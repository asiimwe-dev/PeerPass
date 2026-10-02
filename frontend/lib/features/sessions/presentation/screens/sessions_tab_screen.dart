import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_role.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/sessions/presentation/screens/sessions_list_screen.dart';

class SessionsTabScreen extends ConsumerWidget {
  const SessionsTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

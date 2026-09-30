import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';
import 'package:peerpass/features/sessions/presentation/widgets/session_tile.dart';

/// Every session the signed-in user is part of, split into what is ahead of them
/// and what is behind.
///
/// One request and one screen, rather than tabs per state: a student's question
/// is "which of my sessions is next", and a screen that only ever showed the next
/// one would make them look for a history that was one tap away and not there.
/// The API returns the whole list in its own order and this screen groups it,
/// because "active" is a question about presentation and the server is the only
/// party that knows which of two overlapping sessions ranks higher.
class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);
    final failure = sessions.hasError ? failureFor(sessions.error!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('My sessions')),
      body: SafeArea(
        child: Center(
          child: ContentWidthLimiter(
            // Written as three ordinary branches rather than a pattern match on
            // the `AsyncValue`. `error` and `value` are nullable there, so a
            // pattern that destructures them makes every read a null assertion
            // somewhere else, and the ordering between "failed" and "still
            // loading" ends up expressed as two patterns that have to be read
            // together to see which wins.
            child: switch ((failure, sessions.value)) {
              (final failure?, _) => FailureView(
                // `failureFor` rather than a cast: a provider can fail with
                // something that is not a failure, and rendering the raw error
                // would put a Dart type name on the screen.
                failure: failure,
                // Retried by invalidating rather than by a bespoke reload
                // method, so the button and a pull-to-refresh go through one
                // path and cannot disagree about what "reload" means.
                onRetry: () => ref.invalidate(sessionListProvider),
              ),
              (null, final loaded?) => _Sessions(sessions: loaded),
              _ => const LoadingView(message: 'Loading your sessions'),
            },
          ),
        ),
      ),
    );
  }
}

/// The two sections, or the empty state when there is nothing in either.
class _Sessions extends StatelessWidget {
  const _Sessions({required this.sessions});

  final List<SessionModel> sessions;

  @override
  Widget build(BuildContext context) {
    final active = sessions
        .where((session) => session.isActive)
        .toList(growable: false);
    final past = sessions
        .where((session) => !session.isActive)
        .toList(growable: false);

    // Only when both are empty. A student with three finished sessions and
    // nothing scheduled has a screen to read, not an empty state to apologise
    // for, and telling them they have no sessions would be plainly false.
    if (active.isEmpty && past.isEmpty) {
      return const EmptyView(
        icon: Icons.event_note_outlined,
        title: 'No sessions yet',
        message:
            'Sessions you have with a tutor will appear here, with the PIN you '
            'show them and the meeting link you share.',
      );
    }

    return ListView(
      children: [
        if (active.isNotEmpty) ...[
          const SessionSectionHeader(title: 'Active'),
          for (final session in active) _row(context, session),
        ],
        if (past.isNotEmpty) ...[
          const SessionSectionHeader(title: 'Past'),
          for (final session in past) _row(context, session),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, SessionModel session) {
    return SessionTile(
      session: session,
      onTap: () => context.push(AppRoutes.sessionDetailPath(session.id)),
    );
  }
}

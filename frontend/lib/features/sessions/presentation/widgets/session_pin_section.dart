import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';

/// The two-digit handshake that starts a session in person.
///
/// The team's signature move, and until now invisible: a session is created with
/// a PIN the API generates, the tutee shows it, and the tutor types it to start.
/// Both halves live here because the two are one flow -- a student holding digits
/// and a tutor expecting them -- and splitting them would have meant either two
/// screens or a screen that guessed which one to be.
///
/// The PIN is never generated here. It is displayed or typed, and the API decides
/// whether it was right: a client that could mint or guess a PIN would make the
/// handshake a formality, which is the only thing it is.
///
/// Nothing on this side counts attempts or locks anybody out. Throttling is the
/// API's, and a lock the device enforces is one a student clears by reinstalling
/// the app.
class SessionPinSection extends ConsumerStatefulWidget {
  const SessionPinSection({
    required this.session,
    required this.viewerId,
    super.key,
  });

  final SessionModel session;

  /// The signed-in user's public id, which decides which half of the handshake
  /// this reader is standing on.
  ///
  /// Nullable because the profile loads on its own schedule and a session can be
  /// on screen before it arrives. A null id renders nothing rather than guessing a
  /// side: the PIN goes to one party and not the other, so showing the wrong half
  /// is worse than showing none until the profile lands.
  final String? viewerId;

  @override
  ConsumerState<SessionPinSection> createState() => _SessionPinSectionState();
}

class _SessionPinSectionState extends ConsumerState<SessionPinSection> {
  final _pin = TextEditingController();

  /// Whether the tutee has the digits on screen.
  ///
  /// Local state on purpose, and hidden again on demand: a PIN is shown in a room
  /// with other people in it, so leaving it on screen for the rest of the session
  /// is a longer exposure than the moment the tutor needs it.
  bool _revealed = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final state = ref.watch(sessionDetailProvider(session.id));

    final content = switch (session.status) {
      TutoringSessionStatus.scheduled => switch (widget.viewerId) {
        final viewerId? when session.isTutee(viewerId) => _reveal(context, session),
        final viewerId? when session.isTutor(viewerId) => _enter(context, state),
        _ => null,
      },
      // Once the session is live the handshake has done its job, and the pin is
      // no longer the thing either party needs to see.
      TutoringSessionStatus.inProgress => _started(),
      _ => null,
    };

    // A status that has no handshake -- completed, cancelled, a no-show, or one
    // this client does not recognise -- renders nothing rather than an empty card.
    if (content == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.lg),
        child: content,
      ),
    );
  }

  /// The tutee's half: the digits, to be shown to the tutor.
  Widget _reveal(BuildContext context, SessionModel session) {
    final theme = Theme.of(context);
    final pin = session.sessionPin;

    if (pin == null) {
      return const _Panel(
        icon: Icons.lock_open_outlined,
        title: 'No PIN was issued',
        body:
            'This session has no handshake PIN stored, so it cannot be started '
            'with one. Ask your tutor to start it another way.',
      );
    }

    return _Panel(
      icon: Icons.pin_outlined,
      title: 'Your handshake PIN',
      body:
          'Show these two digits to your tutor. They enter them on their side '
          'and the session starts.',
      trailing: _revealed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  pin,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    // Tabular figures so two digits do not shift as they are
                    // read aloud, which is the one thing this value is for.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppDimens.xs),
                TextButton(
                  onPressed: () => setState(() => _revealed = false),
                  child: const Text('Hide PIN'),
                ),
              ],
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal PIN'),
              ),
            ),
    );
  }

  /// The tutor's half: the digits the student just showed them.
  Widget _enter(BuildContext context, SessionDetailState state) {
    final theme = Theme.of(context);
    final submitting = state.submitting;

    // Two digits is the shape the API documents, so the input refuses anything
    // else before a request is made. This is not the handshake rule -- whether
    // the digits are *right* is still the API's call -- only the shape of the
    // field.
    final readyToSubmit = _pin.text.length == 2 && !submitting;

    return _Panel(
      icon: Icons.dialpad_outlined,
      title: 'Enter the handshake PIN',
      body:
          'Your student is showing you two digits. Enter them here and the '
          'session starts.',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pin,
            enabled: !submitting,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 2,
            // Not a const list: `digitsOnly` is a static field rather than a
            // constructor, and the length limiter carries a value.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: InputDecoration(
              labelText: 'PIN',
              hintText: 'e.g. 42',
              counterText: '',
              errorText: state.pinRejected ? _wrongPin : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: readyToSubmit ? (_) => _submit() : null,
          ),
          const SizedBox(height: AppDimens.md),
          FilledButton(
            onPressed: readyToSubmit ? _submit : null,
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start session'),
          ),
          if (state.actionFailure != null && !state.pinRejected) ...[
            const SizedBox(height: AppDimens.md),
            Text(
              state.actionFailure!.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _started() => const _Panel(
    icon: Icons.play_circle_outline,
    title: 'Handshake complete',
    body: 'The PIN was accepted and this session is live.',
  );

  Future<void> _submit() async {
    final started = await ref
        .read(sessionDetailProvider(widget.session.id).notifier)
        .submitPin(_pin.text);
    // Cleared either way. On success the field is gone with the whole panel; on
    // refusal the digits should not still be in the box for the next attempt.
    if (!mounted) return;
    _pin.clear();
    if (started) setState(() {});
  }
}

/// The wording for a refused PIN.
///
/// Written here rather than taken from the API's `detail`, even though that text
/// is safe to show. The server's sentence is written for a log; this one is
/// written for a tutor standing in front of a student, and it says what to do next
/// rather than only what went wrong. The API's own message is still available
/// through [SessionDetailState.actionFailure] for a client that wants it.
const String _wrongPin = 'That is not the right PIN. Ask your student to check it.';

/// The frame both halves of the handshake share.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppDimens.sm),
            Expanded(
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.xs),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (trailing case final widget?) ...[
          const SizedBox(height: AppDimens.lg),
          widget,
        ],
      ],
    );
  }
}

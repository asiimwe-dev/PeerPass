import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/theme/app_palette.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/empty_view.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/core/widgets/offline_notice.dart';
import 'package:peerpass/features/messages/presentation/providers/session_thread_provider.dart';
import 'package:peerpass/features/messages/presentation/widgets/message_bubble.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';

/// The conversation that belongs to one session.
///
/// The thread is the session, not a chat between two accounts. It opens when a
/// tutor accepts a request -- that is the moment the two of them have a reason to
/// agree on a venue -- and it stays readable afterwards, because the record of
/// what was agreed is the useful part.
///
/// The screen is deliberately small: a header that names the other party, the
/// messages, and a box to type in. Everything else the two of them need is on the
/// session screen behind it.
class SessionChatScreen extends ConsumerStatefulWidget {
  const SessionChatScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<SessionChatScreen> createState() => _SessionChatScreenState();
}

class _SessionChatScreenState extends ConsumerState<SessionChatScreen> {
  final _composer = TextEditingController();
  AppLifecycleListener? _lifecycle;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Polling a thread that is in the background is a request every five seconds
    // for a screen nobody is looking at, on a connection the student is paying
    // for. Pausing is not an optimisation here, it is the difference between a
    // chat that works on a metered phone and one that quietly spends the bundle.
    _lifecycle = AppLifecycleListener(
      onPause: _pause,
      onHide: _pause,
      onResume: _resume,
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _pause() => ref.read(sessionThreadProvider(widget.sessionId).notifier)
      .pause();

  void _resume() => ref.read(sessionThreadProvider(widget.sessionId).notifier)
      .resume();

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final sent = await ref
        .read(sessionThreadProvider(widget.sessionId).notifier)
        .send(text);
    if (!mounted) return;
    setState(() => _sending = false);

    // Only clear on success. A refused message stays in the box so it can be
    // sent again without retyping it, which is the one thing a student on a bad
    // connection will otherwise have to do twice.
    if (sent) _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatSessionProvider(widget.sessionId)).value;
    final viewerId = ref.watch(
      sessionControllerProvider.select((state) => state.profile?.publicId),
    );
    final thread = ref.watch(sessionThreadProvider(widget.sessionId));
    // Closed threads keep their history. A cancelled session is exactly the case
    // where what was agreed last week matters, so the list stays; only the box
    // that would write a reply the API refuses goes away.
    final isClosed = session?.status == TutoringSessionStatus.cancelled ||
        session?.status == TutoringSessionStatus.noShow;

    return Scaffold(
      appBar: AppBar(title: _title(session, viewerId)),
      body: SafeArea(
        top: false,
        child: Center(
          child: ContentWidthLimiter(
            child: Column(
              children: [
                if (thread.pollFailure != null)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppDimens.screenPadding,
                      AppDimens.sm,
                      AppDimens.screenPadding,
                      AppDimens.xs,
                    ),
                    child: OfflineNotice(message: 'Not up to date · retrying'),
                  ),
                Expanded(child: _thread(thread, viewerId)),
                if (isClosed)
                  const _ClosedNotice()
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (thread.sendFailure case final failure?)
                        _SendFailure(failure: failure),
                      _Composer(
                        controller: _composer,
                        sending: _sending,
                        onSend: _send,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thread(SessionThreadState thread, String? viewerId) {
    if (thread.loading) return const LoadingView();

    if (thread.loadFailure case final failure?) {
      return FailureView(
        failure: failure,
        onRetry: () =>
            ref.read(sessionThreadProvider(widget.sessionId).notifier).reload(),
      );
    }

    if (thread.messages.isEmpty) {
      return const EmptyView(
        icon: Icons.forum_outlined,
        title: 'No messages yet',
        message: 'Agree where to meet, or ask about this session.',
      );
    }

    // Reversed, with the list built bottom-up. The newest message is at the top
    // of the reversed list, which is where the reader's eye already is, and it
    // means an arriving message does not scroll the thread out from under someone
    // who was reading it -- the list grows away from the viewer instead.
    final messages = thread.messages.reversed.toList(growable: false);

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPadding,
        vertical: AppDimens.sm,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return MessageBubble(
          key: ValueKey(message.id),
          message: message,
          mine: message.isMine(viewerId),
        );
      },
    );
  }

  /// Who this conversation is with, and what it is about.
  ///
  /// The session is read separately from the thread: a thread opened from a
  /// notification knows only its session id, and a header that waited on the
  /// session would keep the messages hidden behind a second request that is not
  /// needed to read them.
  Widget _title(SessionModel? session, String? viewerId) {
    final theme = Theme.of(context);
    final name = viewerId == null
        ? null
        : session?.otherPartyName(viewerId)?.trim();
    final unit = session?.courseUnitLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name == null || name.isEmpty ? 'Messages' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        if (unit != null)
          Text(
            unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// The box a message is typed in.
///
/// A plain text field and one button. It does not know what a session is, so a
/// refusal is reported by the screen above it and the text it holds is cleared
/// only once the server has taken it.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.screenPadding,
        AppDimens.sm,
        AppDimens.screenPadding,
        AppDimens.sm,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              // The counter is the API's limit, and it is not worth a permanent
              // line under a one-word question. The field still enforces it.
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) => null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Write a message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppDimens.radiusButton),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDimens.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty && !sending;
              return IconButton.filled(
                tooltip: 'Send',
                onPressed: canSend ? onSend : null,
                icon: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Why a session that did not happen has no composer.
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppDimens.screenPadding),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppDimens.sm),
          Expanded(
            child: Text(
              'This session did not take place, so the thread is closed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A send the server refused, with the draft still in the box.
class _SendFailure extends StatelessWidget {
  const _SendFailure({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: palette.coralTint,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPadding,
        vertical: AppDimens.sm,
      ),
      child: Text(
        '${failure.message} Your message is still here.',
        style: theme.textTheme.bodySmall?.copyWith(color: palette.onCoralTint),
      ),
    );
  }
}

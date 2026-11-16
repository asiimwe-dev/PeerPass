import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/messages/data/models/session_message.dart';
import 'package:peerpass/features/messages/data/repositories/messages_repository.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';

/// How often an open thread asks the server for what it does not have.
///
/// A pull model, not a push one. The beta ships without a socket: the message
/// itself is a plain POST, and the thread re-reads with `?after=` while it is on
/// screen. Five seconds is short enough that a reply feels like a reply and long
/// enough that a student on a metered connection is not paying for an empty poll
/// every second. It is a provider so a test can shorten it, and so the WebSocket
/// upgrade has one number to delete rather than a constant to hunt down.
final messagePollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// The session this thread belongs to.
///
/// Read through the sessions feature's *repository contract*, not its screens:
/// the chat needs the other party's name and the topic for its header, and it
/// must not import another feature's presentation. A route into a thread from a
/// notification therefore loads the session itself rather than assuming it was
/// opened from the session screen.
// Riverpod surfaces the family's type through generics the analyzer cannot name
// for the declaration; the explicit ignore is the same one the sessions
// providers carry.
// ignore: specify_nonobvious_property_types
final chatSessionProvider = FutureProvider.autoDispose.family<SessionModel, String>(
  (ref, sessionId) =>
      ref.read(sessionsRepositoryProvider).session(sessionId),
  retry: (retryCount, error) => null,
);

/// One thread, as its screen sees it.
///
/// Keeps the loaded messages and the two failures apart: a thread that could not
/// be read at all is worth a retry button, and a message that was refused is
/// worth keeping the typed text on screen. An [AsyncValue] of the list would
/// have to report one and throw the other away.
@immutable
class SessionThreadState {
  const SessionThreadState({
    this.messages = const [],
    this.loading = true,
    this.loadFailure,
    this.sending = false,
    this.sendFailure,
    this.pollFailure,
  });

  final List<SessionMessage> messages;

  /// Whether the first read is still in flight.
  final bool loading;

  /// Why the thread could not be read. Retryable, and shown instead of the list.
  final Failure? loadFailure;

  final bool sending;

  /// Why the last send was refused. The draft is kept so it can be sent again.
  final Failure? sendFailure;

  /// Why the last background refresh failed, while what is on screen is still
  /// readable. Shown as one line, never as a replacement for the thread.
  final Failure? pollFailure;

  /// Whether the thread has loaded and has nothing in it.
  bool get isEmpty => !loading && loadFailure == null && messages.isEmpty;

  SessionThreadState copyWith({
    List<SessionMessage>? messages,
    bool? loading,
    bool? sending,
    Failure? loadFailure,
    Failure? sendFailure,
    Failure? pollFailure,
    bool clearLoadFailure = false,
    bool clearSendFailure = false,
    bool clearPollFailure = false,
  }) {
    return SessionThreadState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
      sending: sending ?? this.sending,
      sendFailure: clearSendFailure ? null : (sendFailure ?? this.sendFailure),
      pollFailure: clearPollFailure ? null : (pollFailure ?? this.pollFailure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionThreadState &&
          listEquals(other.messages, messages) &&
          other.loading == loading &&
          other.loadFailure == loadFailure &&
          other.sending == sending &&
          other.sendFailure == sendFailure &&
          other.pollFailure == pollFailure;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(messages),
    loading,
    loadFailure,
    sending,
    sendFailure,
    pollFailure,
  );
}

/// The thread for one session, loaded once and refreshed while it is open.
///
/// Auto-disposed with the screen, which is what stops the poll: a chat that is
/// not on screen has no reason to ask anything. That matters on a metered
/// connection -- polling every thread a student ever opened would spend their
/// data on conversations they are not reading.
// Riverpod infers the family's type from the generics; the declaration needs it
// spelled out for the analyzer.
// ignore: specify_nonobvious_property_types
final sessionThreadProvider =
    NotifierProvider.autoDispose.family<
      SessionThreadController,
      SessionThreadState,
      String
    >(SessionThreadController.new);

class SessionThreadController extends Notifier<SessionThreadState> {
  SessionThreadController(this.sessionId);

  final String sessionId;

  Timer? _timer;
  bool _polling = false;
  Duration _interval = const Duration(seconds: 5);

  MessagesRepository get _repository => ref.read(messagesRepositoryProvider);

  String? get _viewerId => ref.read(sessionControllerProvider).profile?.publicId;

  @override
  SessionThreadState build() {
    // The thread belongs to whoever is signed in. Watching the id makes an
    // account switch reopen it as the new account instead of leaving the
    // previous student's conversation on screen.
    final viewerId = ref.watch(
      sessionControllerProvider.select((session) => session.profile?.publicId),
    );
    _interval = ref.watch(messagePollIntervalProvider);
    ref.onDispose(_stop);
    _timer?.cancel();
    _timer = null;

    if (viewerId == null) {
      return const SessionThreadState(loading: false);
    }

    // Kicked off rather than awaited: `build` is synchronous, and the first
    // frame should be a composer, not a blank screen held on the network.
    unawaited(_load());
    return const SessionThreadState();
  }

  /// Re-reads the thread from the beginning, for the retry button.
  Future<void> reload() async {
    _stop();
    state = const SessionThreadState();
    await _load();
  }

  /// Sends one message, returning whether the server took it.
  ///
  /// The trim here is a courtesy, not the rule: the API trims too, and a client
  /// that trimmed differently would send a body the other party reads without
  /// its surrounding whitespace anyway. Empty is not sent at all, because a blank
  /// message would still mark the other party's thread unread.
  Future<bool> send(String body) async {
    final text = body.trim();
    if (text.isEmpty || state.sending) return false;

    state = state.copyWith(sending: true, clearSendFailure: true);
    try {
      final message = await _repository.send(sessionId: sessionId, body: text);
      if (!ref.mounted) return true;
      // A poll can deliver the row before the POST returns. Appending it again
      // would show the student their own message twice.
      final already = state.messages.any((row) => row.id == message.id);
      state = state.copyWith(
        messages: already ? state.messages : [...state.messages, message],
        sending: false,
      );
      return true;
    } on Object catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(sending: false, sendFailure: failureFor(error));
      return false;
    }
  }

  /// Stops asking while the app is in the background.
  void pause() => _stop();

  /// Resumes asking when the app returns to the foreground.
  ///
  /// Polls immediately rather than waiting out the interval: coming back to the
  /// app is exactly the moment the student expects it to be current.
  void resume() {
    if (!state.loading && state.loadFailure == null) {
      unawaited(_poll());
      _startPolling();
    }
  }

  Future<void> _load() async {
    try {
      final messages = await _repository.messages(sessionId);
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: messages,
        loading: false,
        clearLoadFailure: true,
        clearPollFailure: true,
      );
      await _markRead(messages);
      _startPolling();
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadFailure: failureFor(error));
    }
  }

  /// Asks for what arrived after the newest message on screen.
  Future<void> _poll() async {
    if (_polling || state.loading || state.loadFailure != null) return;
    _polling = true;
    try {
      final last = state.messages.isEmpty ? null : state.messages.last.id;
      final fresh = await _repository.messages(sessionId, after: last);
      if (!ref.mounted) return;
      if (fresh.isEmpty) {
        // An empty poll is the common answer and clears a warning left by an
        // earlier one, which is what makes the line disappear without a reload.
        if (state.pollFailure != null) {
          state = state.copyWith(clearPollFailure: true);
        }
        return;
      }
      state = state.copyWith(
        messages: [...state.messages, ...fresh],
        clearPollFailure: true,
      );
      await _markRead(fresh);
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(pollFailure: failureFor(error));
    } finally {
      _polling = false;
    }
  }

  /// Tells the server the other party's new messages were read.
  ///
  /// Only when something is actually unread: the endpoint is idempotent, but a
  /// write on every empty poll would be a request every five seconds that changes
  /// nothing. A failure here is not shown: the message is readable either way,
  /// and the next poll or the next open will try again.
  Future<void> _markRead(List<SessionMessage> rows) async {
    final viewerId = _viewerId;
    final unread = rows.any(
      (row) => !row.isMine(viewerId) && !row.isRead,
    );
    if (!unread) return;
    try {
      await _repository.markRead(sessionId: sessionId);
    } on Object {
      // Left unread on the server, so the badge stays until it succeeds. The
      // thread is still usable, and a snackbar for a badge would be noise.
    }
  }

  void _startPolling() {
    // Reachable after an await -- `_load` starts the timer once the mark-read
    // call has answered. If the screen was closed while that request was in
    // flight, `onDispose` has already run, so a timer created here would have
    // nothing left to cancel it: one request every five seconds for the rest of
    // the app's life, for a thread nobody is reading.
    if (!ref.mounted || _timer != null) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(_poll()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}

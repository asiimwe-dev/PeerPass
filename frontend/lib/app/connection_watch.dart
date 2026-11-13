import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';

/// Watches for a session that is running on saved data and reconnects on its own.
///
/// The offline notice is information, not an instruction. A student who was
/// reading their session list when the connection dropped should not have to
/// know that pull-to-refresh is the way back: the app knows it is offline, so the
/// app is the one that should be retrying. Refresh stays available for the times
/// the student wants to force it.
///
/// Retries back off (5s, 10s, 20s, then every 40s) because a device with no
/// network would otherwise spend the whole battery re-dialling a server that is
/// not there. Returning to the foreground retries immediately, since coming back
/// to the app is the moment a student expects it to be current again.
///
/// The next attempt is scheduled *before* the current one is awaited. A request
/// that hangs -- a socket the server closed under us, a radio that never admits
/// it is gone -- would otherwise keep the attempt in flight forever and stop the
/// retries with it, which is the one failure mode the student would experience as
/// "it never comes back". Overlapping attempts are harmless: the auth controller
/// drops all but the newest.
class ConnectionWatch extends ConsumerStatefulWidget {
  const ConnectionWatch({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ConnectionWatch> createState() => _ConnectionWatchState();
}

class _ConnectionWatchState extends ConsumerState<ConnectionWatch> {
  static const _firstDelay = Duration(seconds: 5);
  static const _maxDelay = Duration(seconds: 40);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Duration _delay = _firstDelay;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _scheduleIfOffline(ref.read(sessionControllerProvider).isOffline);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Schedules the next attempt, or stops trying when there is nothing to fix.
  ///
  /// The delay grows only while offline, so a single dropped connection does not
  /// leave the app crawling back at forty-second intervals for the rest of the
  /// session.
  void _scheduleIfOffline(bool isOffline) {
    _timer?.cancel();
    _timer = null;
    if (!isOffline) {
      _delay = _firstDelay;
      return;
    }
    final delay = _delay;
    _delay = delay * 2 > _maxDelay ? _maxDelay : delay * 2;
    _timer = Timer(delay, _attempt);
  }

  Future<void> _attempt() async {
    if (_disposed) return;
    // Scheduled first: whether this attempt answers, fails, or hangs, another
    // one follows.
    _scheduleIfOffline(ref.read(sessionControllerProvider).isOffline);
    try {
      await ref.read(authControllerProvider).retryRestore();
    } on Object {
      // The next attempt is already scheduled, and the screen already says
      // there is no connection. Nothing here is worth a second error report.
    }
  }

  void _onResume() {
    if (!ref.read(sessionControllerProvider).isOffline) return;
    _timer?.cancel();
    _timer = null;
    _delay = _firstDelay;
    unawaited(_attempt());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (previous?.isOffline == next.isOffline) return;
      _delay = _firstDelay;
      _scheduleIfOffline(next.isOffline);
    });
    return widget.child;
  }
}

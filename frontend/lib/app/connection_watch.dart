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
  bool _retrying = false;
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

  void _scheduleIfOffline(bool isOffline) {
    _timer?.cancel();
    _timer = null;
    if (!isOffline || _disposed) {
      _delay = _firstDelay;
      return;
    }
    _timer = Timer(_delay, _retry);
  }

  Future<void> _retry() async {
    if (_retrying || _disposed) return;
    _retrying = true;
    try {
      await ref.read(authControllerProvider).retryRestore();
    } finally {
      _retrying = false;
    }
    if (_disposed) return;
    // The listener has already re-scheduled on success. Waiting longer on
    // failure is what keeps a phone in a tunnel from retrying every five
    // seconds until it is charged.
    _delay = _delay * 2 > _maxDelay ? _maxDelay : _delay * 2;
    _scheduleIfOffline(ref.read(sessionControllerProvider).isOffline);
  }

  void _onResume() {
    if (!ref.read(sessionControllerProvider).isOffline) return;
    _delay = _firstDelay;
    unawaited(_retry());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (previous?.isOffline == next.isOffline) return;
      _scheduleIfOffline(next.isOffline);
    });
    return widget.child;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/theme/app_theme.dart';

/// The application root.
///
/// Holds nothing but wiring: theme, router, and the providers the router needs
/// in order to make a redirect decision. Keeping it free of feature logic means
/// the shell can be replaced or removed without touching a feature.
class PeerPassApp extends ConsumerWidget {
  const PeerPassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'PeerPass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

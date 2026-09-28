import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/splash_screen.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';
import 'package:peerpass/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:peerpass/features/home/presentation/screens/home_screen.dart';

/// Every location the shell can be at.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String signIn = '/sign-in';
  static const String home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
    // go_router re-evaluates this on every navigation and whenever the
    // listenable fires, which is what makes an auth change redirect the app
    // from wherever it is without the screen asking for it.
    refreshListenable: _AuthChangeNotifier(ref),
    redirect: (context, state) => _redirectFor(
      ref.read(authControllerProvider).status,
      state.matchedLocation,
    ),
  );

  ref.onDispose(router.dispose);
  return router;
});

/// The one place that decides where an auth status is allowed to lead.
///
/// Pure and string-in/string-out so the guard can be tested directly, without
/// standing up a router, a widget tree, or a session.
String? _redirectFor(AuthStatus status, String location) {
  return switch (status) {
    // Nothing is known yet. Stay put only if already waiting; otherwise hold
    // the app on splash rather than guessing and flashing the wrong screen.
    AuthStatus.unknown =>
      location == AppRoutes.splash ? null : AppRoutes.splash,
    AuthStatus.unauthenticated =>
      location == AppRoutes.signIn ? null : AppRoutes.signIn,
    // A signed-in user is sent home from everywhere, including a deep link to
    // sign-in, so a bookmarked sign-in URL cannot strand them on it.
    AuthStatus.authenticated =>
      location == AppRoutes.home ? null : AppRoutes.home,
  };
}

/// Bridges a Riverpod provider to the `Listenable` go_router expects.
///
/// go_router predates Riverpod and has no adapter of its own, so the shell
/// supplies one rather than adding a dependency for a single interface.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    _subscription = ref.listen<AuthState>(
      authControllerProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/splash_screen.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';
import 'package:peerpass/features/auth/presentation/screens/become_tutor_screen.dart';
import 'package:peerpass/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:peerpass/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:peerpass/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:peerpass/features/home/presentation/screens/home_screen.dart';

/// Every location the shell can be at.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String onboarding = '/onboarding';
  static const String tutorVerification = '/tutor-verification';
  static const String home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Reading the controller is what starts the cold-start check of the stored
  // session. It has to happen before the first redirect is evaluated, or the
  // app would hold on splash until something else happened to read it.
  ref.read(authControllerProvider);

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
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.tutorVerification,
        builder: (context, state) => const BecomeTutorScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
    // go_router re-evaluates this on every navigation and whenever the
    // listenable fires, which is what makes an auth change redirect the app
    // from wherever it is without the screen asking for it.
    refreshListenable: _SessionChangeNotifier(ref),
    redirect: (context, state) => _redirectFor(
      ref.read(sessionControllerProvider),
      state.matchedLocation,
    ),
  );

  ref.onDispose(router.dispose);
  return router;
});

/// The one place that decides where an auth status is allowed to lead.
///
/// Pure and takes the whole session rather than the status alone, because a
/// signed-in student is not automatically allowed home -- one with no name or no
/// university has to run the wizard first. Passing only the status would have
/// forced that distinction back out into every call site.
String? _redirectFor(SessionState state, String location) {
  return switch (state.status) {
    // Nothing is known yet. Stay put only if already waiting; otherwise hold
    // the app on splash rather than guessing and flashing the wrong screen.
    SessionStatus.unknown =>
      location == AppRoutes.splash ? null : AppRoutes.splash,
    // Sign-in and sign-up are both reachable while signed out, and the two must
    // be listed together. Exempting only sign-in made the guard redirect a
    // student off the sign-up screen the instant they arrived, so "No account
    // yet? Create one" did nothing at all: the button navigated, the guard
    // undid it, and the screen never rendered. The screen itself was correct and
    // its widget tests passed, because they pumped it directly and never went
    // through here.
    SessionStatus.unauthenticated =>
      _isPublicAuthRoute(location) ? null : AppRoutes.signIn,
    SessionStatus.authenticated => _redirectForSignedIn(state.profile, location),
  };
}

/// The two routes a signed-out student is allowed to be on.
///
/// Shared by both branches of the guard deliberately. The signed-in branch has
/// to reject these and the signed-out branch has to accept them, and writing the
/// pair out separately is how the two halves drifted apart in the first place.
bool _isPublicAuthRoute(String location) =>
    location == AppRoutes.signIn || location == AppRoutes.signUp;

/// Where a signed-in student belongs.
String? _redirectForSignedIn(UserProfile? profile, String location) {
  // Sign-in and sign-up are the two places a signed-in student must not be, or
  // a bookmarked /sign-in link would strand them in a form that cannot succeed.
  if (_isPublicAuthRoute(location)) {
    return _landingFor(profile);
  }

  // `needsOnboarding` is the profile's own answer, so the definition of "still
  // incomplete" exists once, in the model, and not again here.
  final needsOnboarding = profile?.needsOnboarding ?? true;

  if (needsOnboarding) {
    return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
  }

  if (location == AppRoutes.tutorVerification) {
    return null;
  }

  // Onboarding is not a place a complete account can remain: once the profile
  // is finished the guard moves it home, which is also what ends the wizard
  // after its last step.
  return location == AppRoutes.home ? null : AppRoutes.home;
}

String _landingFor(UserProfile? profile) =>
    (profile?.needsOnboarding ?? true) ? AppRoutes.onboarding : AppRoutes.home;

/// Bridges the session to the `Listenable` go_router expects.
///
/// go_router predates Riverpod and has no adapter of its own, so the shell
/// supplies one rather than adding a dependency for a single interface.
class _SessionChangeNotifier extends ChangeNotifier {
  _SessionChangeNotifier(Ref ref) {
    _subscription = ref.listen<SessionState>(
      sessionControllerProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

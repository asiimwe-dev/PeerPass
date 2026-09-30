import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/splash_screen.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/user_profile.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';
import 'package:peerpass/features/auth/presentation/screens/become_tutor_screen.dart';
import 'package:peerpass/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:peerpass/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:peerpass/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:peerpass/features/home/presentation/screens/home_screen.dart';
import 'package:peerpass/features/matching/presentation/screens/course_unit_picker_screen.dart';
import 'package:peerpass/features/matching/presentation/screens/match_results_screen.dart';
import 'package:peerpass/features/sessions/presentation/screens/rate_session_screen.dart';
import 'package:peerpass/features/sessions/presentation/screens/session_detail_screen.dart';
import 'package:peerpass/features/sessions/presentation/screens/sessions_list_screen.dart';
import 'package:peerpass/features/sessions/presentation/widgets/active_session_card.dart';
import 'package:peerpass/features/tutors/presentation/screens/tutor_detail_screen.dart';
import 'package:peerpass/features/tutors/presentation/widgets/tutor_rail.dart';

/// Every location the shell can be at.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String onboarding = '/onboarding';
  static const String tutorVerification = '/tutor-verification';
  static const String home = '/home';
  static const String sessions = '/sessions';
  static const String tutors = '/tutors';
  static const String matching = '/matching';

  /// One tutor's profile, opened from the rail.
  ///
  /// A path rather than a query, so the link to a tutor is something a student
  /// can put in a message to a classmate and have it open the same profile.
  static String tutorDetailPath(String userId) => '$tutors/$userId';

  /// The tutors the API will propose for one course unit.
  ///
  /// The unit is in the path for the same reason the session id is: the screen
  /// that answers "who can help with this course" is not reachable without the
  /// course, and a route that could not name it would be a link to nothing.
  static String matchResultsPath(String courseUnitId) =>
      '$matching/$courseUnitId';

  /// The list, a session, and that session's rating form.
  ///
  /// Written as helpers rather than string-concatenated at the call site, because
  /// the rating form is a *sibling* of the session it is about and both are
  /// children of the list. A path built by hand at the call site is one missing
  /// segment away from a route that exists and a screen that does not.
  static String sessionDetailPath(String sessionId) => '$sessions/$sessionId';

  static String rateSessionPath(String sessionId) => '$sessions/$sessionId/rate';
}

/// The session id out of a matched route, or the honest answer that there isn't one.
///
/// `/sessions` with a trailing slash matches the detail route with an empty
/// parameter. That is a link a person can type and a client can be handed, and
/// indexing an absent id would take the app down over a URL.
String? _sessionIdOf(GoRouterState state) => _idOf(state, 'sessionId');

/// A path parameter that is missing or empty.
///
/// One helper for every route with an id in its path. Three separate copies of
/// the same null-and-empty check is how one of them ends up accepting the empty
/// string that the other two reject.
String? _idOf(GoRouterState state, String parameter) {
  final id = state.pathParameters[parameter];
  if (id == null || id.isEmpty) return null;
  return id;
}

/// What a link with no id in it gets.
///
/// A sentence rather than a redirect: the link is malformed, and silently
/// sending a student somewhere else would leave them on a screen that has
/// nothing to do with what they asked for and no way to tell that anything went
/// wrong.
class _MissingIdRoute extends StatelessWidget {
  const _MissingIdRoute({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.lg),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
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
        builder: (context, state) => const HomeScreen(
          activeSessionCard: ActiveSessionCard(),
          // Passed in rather than built here for the reason [HomeScreen]
          // documents: home must not import a feature it owns nothing of. The
          // rail is a section of the dashboard, not a route, so it has no path
          // to be reached by and so the shell is the only thing that can supply
          // it.
          tutorRail: TutorRail(),
        ),
      ),
      GoRoute(
        path: AppRoutes.sessions,
        builder: (context, state) => const SessionsListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.sessions}/:sessionId',
        builder: (context, state) {
          final sessionId = _sessionIdOf(state);
          if (sessionId == null) {
            return const _MissingIdRoute(
              title: 'Session',
              message: 'That link does not name a session.',
            );
          }
          return SessionDetailScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: '${AppRoutes.sessions}/:sessionId/rate',
        builder: (context, state) {
          final sessionId = _sessionIdOf(state);
          if (sessionId == null) {
            return const _MissingIdRoute(
              title: 'Session',
              message: 'That link does not name a session.',
            );
          }
          return RateSessionScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: '${AppRoutes.tutors}/:userId',
        builder: (context, state) {
          final userId = _idOf(state, 'userId');
          if (userId == null) {
            return const _MissingIdRoute(
              title: 'Tutor',
              message: 'That link does not name a tutor.',
            );
          }
          return TutorDetailScreen(userId: userId);
        },
      ),
      GoRoute(
        path: AppRoutes.matching,
        builder: (context, state) => const CourseUnitPickerScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.matching}/:courseUnitId',
        builder: (context, state) {
          final courseUnitId = _idOf(state, 'courseUnitId');
          if (courseUnitId == null) {
            return const _MissingIdRoute(
              title: 'Find a tutor',
              message: 'That link does not name a course unit.',
            );
          }
          return MatchResultsScreen(courseUnitId: courseUnitId);
        },
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

  // The whole sessions subtree, not just its two screens. A signed-in student who
  // follows a link to a session, or who is on the rating form for one, is exactly
  // as allowed to be there as one who walked there from home, and the guard that
  // bounced them to the dashboard mid-flow was a redirect with no reason to exist.
  //
  // Tutor profiles and matching are allowed for the same reason and for a second
  // one: they are reached *from* home and from the rail, so a guard that only
  // exempted home and sessions would let a student tap a tutor's card and be
  // returned to the dashboard, which reads as the app refusing to open the thing
  // they just pressed.
  if (_isSessionRoute(location) ||
      _isTutorRoute(location) ||
      _isMatchingRoute(location)) {
    return null;
  }

  // Onboarding is not a place a complete account can remain: once the profile
  // is finished the guard moves it home, which is also what ends the wizard
  // after its last step.
  return location == AppRoutes.home ? null : AppRoutes.home;
}

/// Whether a location is inside the sessions subtree.
bool _isSessionRoute(String location) =>
    location == AppRoutes.sessions ||
    location.startsWith('${AppRoutes.sessions}/');

/// Whether a location is a tutor profile.
bool _isTutorRoute(String location) =>
    location.startsWith('${AppRoutes.tutors}/');

/// Whether a location is inside the matching subtree.
bool _isMatchingRoute(String location) =>
    location == AppRoutes.matching ||
    location.startsWith('${AppRoutes.matching}/');

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

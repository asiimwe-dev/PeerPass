import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/app/app.dart';
import 'package:peerpass/core/config/app_config.dart';
import 'package:peerpass/core/network/api_client.dart';
import 'package:peerpass/core/storage/session_cache.dart';
import 'package:peerpass/core/storage/token_store.dart';
import 'package:peerpass/features/auth/data/datasources/remote_academics_datasource.dart';
import 'package:peerpass/features/auth/data/datasources/remote_auth_datasource.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/auth/data/repositories/remote_auth_repository.dart';
import 'package:peerpass/features/competencies/data/datasources/remote_competencies_datasource.dart';
import 'package:peerpass/features/competencies/data/repositories/competencies_repository.dart';
import 'package:peerpass/features/competencies/data/repositories/remote_competencies_repository.dart';
import 'package:peerpass/features/incentives/data/datasources/remote_incentives_datasource.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';
import 'package:peerpass/features/incentives/data/repositories/remote_incentives_repository.dart';
import 'package:peerpass/features/matching/data/datasources/remote_matching_datasource.dart';
import 'package:peerpass/features/matching/data/repositories/matching_repository.dart';
import 'package:peerpass/features/matching/data/repositories/remote_matching_repository.dart';
import 'package:peerpass/features/messages/data/datasources/remote_messages_datasource.dart';
import 'package:peerpass/features/messages/data/repositories/messages_repository.dart';
import 'package:peerpass/features/messages/data/repositories/remote_messages_repository.dart';
import 'package:peerpass/features/notifications/data/datasources/remote_notifications_datasource.dart';
import 'package:peerpass/features/notifications/data/repositories/notifications_repository.dart';
import 'package:peerpass/features/notifications/data/repositories/remote_notifications_repository.dart';
import 'package:peerpass/features/sessions/data/datasources/remote_sessions_datasource.dart';
import 'package:peerpass/features/sessions/data/repositories/remote_sessions_repository.dart';
import 'package:peerpass/features/sessions/data/repositories/sessions_repository.dart';
import 'package:peerpass/features/tutors/data/datasources/remote_tutors_datasource.dart';
import 'package:peerpass/features/tutors/data/repositories/remote_tutors_repository.dart';
import 'package:peerpass/features/tutors/data/repositories/tutors_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final tokenStore = SecureTokenStore();
  SessionCache? sessionCache;
  try {
    final cache = SessionCache();
    await cache.open();
    sessionCache = cache;
  } on Exception {
    // History is an optional enhancement. A corrupt encrypted cache must not
    // prevent the online sign-in flow from rendering; the next successful
    // session can recreate it through the normal cache path.
    sessionCache = null;
  }

  // The refresh callback and the repository refer to each other: the
  // interceptor needs to be able to refresh, and refreshing is a repository
  // call, but the repository needs the client the interceptor is attached to.
  //
  // `late final` resolves this the same way `api_client.dart` already does for
  // its own retry closure. The callback cannot run before the assignment,
  // because nothing issues a request until the repository exists.
  late final RemoteAuthRepository repository;

  final dio = buildApiClient(
    config: config,
    tokenStore: tokenStore,
    // A closure rather than the tear-off `repository.refreshSession`. The
    // tear-off reads `repository` here, at the point of construction, and the
    // flow analysis correctly says it is not assigned yet. Inside a closure the
    // read is deferred, which is the same trick `buildApiClient` already uses
    // for its own retry.
    onUnauthorized: () => repository.refreshSession(),
  );

  repository = RemoteAuthRepository(
    auth: RemoteAuthDatasource(dio),
    academics: RemoteAcademicsDatasource(dio, cache: sessionCache),
    tokenStore: tokenStore,
  );

  final sessionsRepository = RemoteSessionsRepository(
    RemoteSessionsDatasource(dio, cache: sessionCache),
  );

  // One `Dio` for every datasource, so the token, the refresh and the retry
  // behave the same on a matching request as on a session request. Building a
  // second client per feature would give each of them its own token store and
  // its own idea of whether the user is signed in.
  final tutorsRepository = RemoteTutorsRepository(
    RemoteTutorsDatasource(dio, cache: sessionCache),
  );
  final matchingRepository = RemoteMatchingRepository(
    RemoteMatchingDatasource(dio, cache: sessionCache),
  );
  final messagesRepository = RemoteMessagesRepository(
    RemoteMessagesDatasource(dio),
  );
  final notificationsRepository = RemoteNotificationsRepository(
    RemoteNotificationsDatasource(dio),
  );
  final incentivesRepository = RemoteIncentivesRepository(
    RemoteIncentivesDatasource(dio),
  );
  final competenciesRepository = RemoteCompetenciesRepository(
    datasource: RemoteCompetenciesDatasource(dio),
  );

  runApp(
    ProviderScope(
      // The composition root. Choosing implementations here, rather than
      // defaulting them in the providers, is what makes a test swap the whole
      // data layer for a fake in one line.
      //
      // `sessionsRepositoryProvider`, `tutorsRepositoryProvider`,
      // `matchingRepositoryProvider`, `messagesRepositoryProvider`,
      // `notificationsRepositoryProvider`, `incentivesRepositoryProvider` and
      // `competenciesRepositoryProvider` all throw unless they are overridden, so
      // leaving one out does not degrade to a fake that quietly reports no
      // sessions, no tutors, no messages and nobody eligible: the failure is
      // immediate and names the missing override.
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        sessionCacheProvider.overrideWithValue(sessionCache),
        sessionsRepositoryProvider.overrideWithValue(sessionsRepository),
        tutorsRepositoryProvider.overrideWithValue(tutorsRepository),
        matchingRepositoryProvider.overrideWithValue(matchingRepository),
        messagesRepositoryProvider.overrideWithValue(messagesRepository),
        notificationsRepositoryProvider.overrideWithValue(
          notificationsRepository,
        ),
        incentivesRepositoryProvider.overrideWithValue(incentivesRepository),
        competenciesRepositoryProvider.overrideWithValue(
          competenciesRepository,
        ),
      ],
      child: const PeerPassApp(),
    ),
  );
}

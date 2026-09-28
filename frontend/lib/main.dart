import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/app/app.dart';
import 'package:peerpass/features/auth/data/datasources/in_memory_auth_datasource.dart';
import 'package:peerpass/features/auth/data/repositories/in_memory_auth_repository.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        // The composition root. Choosing implementations here, rather than
        // defaulting them in the providers, is what makes the swap to the real
        // API a one-line change instead of a search.
        authRepositoryProvider.overrideWithValue(
          InMemoryAuthRepository(InMemoryAuthDatasource()),
        ),
      ],
      child: const PeerPassApp(),
    ),
  );
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ulearn/app/app.dart';
import 'package:ulearn/features/auth/data/datasources/in_memory_auth_datasource.dart';
import 'package:ulearn/features/auth/data/repositories/in_memory_auth_repository.dart';
import 'package:ulearn/features/auth/presentation/providers/auth_providers.dart';

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
      child: const UlearnApp(),
    ),
  );
}

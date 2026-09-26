import 'package:ulearn/features/auth/data/datasources/in_memory_auth_datasource.dart';
import 'package:ulearn/features/auth/data/models/auth_session.dart';
import 'package:ulearn/features/auth/data/repositories/auth_repository.dart';

/// [AuthRepository] over an in-memory datasource.
class InMemoryAuthRepository implements AuthRepository {
  const InMemoryAuthRepository(this._datasource);

  final InMemoryAuthDatasource _datasource;

  @override
  Future<AuthSession?> restoreSession() => _datasource.restoreSession();

  @override
  Future<void> signOut() async {
    _datasource.session = null;
    await _datasource.clearTokens();
  }
}

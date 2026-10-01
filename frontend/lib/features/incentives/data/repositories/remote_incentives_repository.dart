import 'package:dio/dio.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/network/network_exceptions.dart';
import 'package:peerpass/features/incentives/data/datasources/remote_incentives_datasource.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';

/// [IncentivesRepository] over the real API.
///
/// The only layer that knows both the wire format and the failure hierarchy. The
/// `_guard` helper below is the fourth copy of the one in
/// `remote_auth_repository.dart`, `remote_sessions_repository.dart` and
/// `remote_tutors_repository.dart`, duplicated rather than lifted into `core/`
/// because hoisting it means editing files this feature does not own. Four deep
/// is the note that lifting it is now overdue.
class RemoteIncentivesRepository implements IncentivesRepository {
  const RemoteIncentivesRepository(this._remote);

  final RemoteIncentivesDatasource _remote;

  @override
  Future<CertificateEligibility> myCertificate() {
    // The whole body is inside the guard, including the parse. A malformed
    // response is a server fault, and a `fromJson` that ran after the guard
    // returned would throw past every translation here and reach the screen as a
    // bare `FormatException`.
    return _guard(() async => CertificateEligibility.fromJson(await _remote.myCertificate()));
  }

  /// Runs a call and translates whatever comes back into a [Failure].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Object catch (error) {
      throw _toFailure(error);
    }
  }

  Failure _toFailure(Object error) {
    if (error is Failure) return error;
    if (error is FormatException) {
      // The API answered with something that is not the shape it documents.
      return const ServerFailure(
        'The server sent something we could not read.',
      );
    }
    if (error is DioException) return mapDioException(error);
    return const UnknownFailure();
  }
}

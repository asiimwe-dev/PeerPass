import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/competencies/data/models/application_limits.dart';
import 'package:peerpass/features/competencies/data/models/tutor_claim.dart';

/// The tutor-competency contract the client depends on.
///
/// Every method throws a [Failure], never a transport exception. Translating
/// `DioException` and RFC 9457 problem documents into [Failure] happens in the
/// implementation, so a screen renders a message and never has to know whether
/// the API answered with a socket error or a problem document.
abstract interface class CompetenciesRepository {
  /// Every proof the signed-in user has submitted, newest first.
  ///
  /// Empty when they have submitted none. Not an error, and not gated on the
  /// tutor role: this is how a student finds out they have not applied yet.
  Future<List<TutorClaim>> myClaims();

  /// How many live claims the caller holds, and the cap the API enforces.
  ///
  /// Live means pending or verified. A rejected claim does not consume a slot,
  /// because resubmitting after a rejection must stay possible.
  Future<ApplicationLimits> applicationLimits();

  /// Submits proof for a unit the user claims to know.
  ///
  /// Returns the stored claim. A unit whose previous claim was rejected is
  /// reopened by this call rather than refused, so a tutor can answer a reviewer's
  /// reason; a unit with a pending or verified claim is refused by the API.
  Future<TutorClaim> submitClaim({
    required String courseUnitId,
    required String gradeId,
    required String source,
    String? evidenceReference,
    String? notes,
  });
}

/// The repository used by the tutor-proof flows and account status summary.
final competenciesRepositoryProvider = Provider<CompetenciesRepository>(
  (ref) => throw UnimplementedError(
    'competenciesRepositoryProvider must be overridden in ProviderScope.',
  ),
);

/// The signed-in user's submitted tutor applications.
final myClaimsProvider = FutureProvider<List<TutorClaim>>(
  (ref) => ref.read(competenciesRepositoryProvider).myClaims(),
  retry: (retryCount, error) => null,
);

/// The signed-in user's active application count and the configured cap.
///
/// Separate from [myClaimsProvider] so a limits failure cannot hide the claims
/// list: the screen still has something true to show even when it cannot say
/// whether another application is allowed.
final applicationLimitsProvider = FutureProvider<ApplicationLimits>(
  (ref) => ref.read(competenciesRepositoryProvider).applicationLimits(),
  retry: (retryCount, error) => null,
);

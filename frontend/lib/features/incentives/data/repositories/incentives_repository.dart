import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';

/// The incentives contract the screens depend on.
///
/// Every method throws a [Failure], never a transport exception and never a
/// `FormatException`. Translating `DioException`, problem documents, and
/// unparseable bodies into [Failure] happens in the implementation, so a screen
/// renders a message and never has to know whether the API answered with a
/// socket error, a 401, or a body that was not the shape it documents.
abstract interface class IncentivesRepository {
  /// The signed-in user's own certificate eligibility.
  ///
  /// There is no user parameter, and that is the contract rather than an
  /// omission: these are the caller's own hours, the API will answer about
  /// nobody else, and a method that could be handed somebody else's id would be
  /// a method whose safety depended on every caller.
  ///
  /// A caller with no tutor profile is a normal answer and not a failure: they
  /// are not a tutor yet, which is a state the screen renders rather than an
  /// error it apologises for.
  Future<CertificateEligibility> myCertificate();
}

/// The incentives contract, as a live instance.
///
/// Declared in the contract file rather than beside the incentives screens, for
/// the same reason `sessionsRepositoryProvider` is: this is the handle by which
/// other features reach this feature, and a provider living in `presentation/`
/// could not be imported by a sibling feature without also importing its
/// screens.
///
/// Throwing rather than defaulting keeps a missing override loud, for the same
/// reason the other three do: a silent default would ship a screen whose numbers
/// were invented, and the composition root in `main.dart` is what has to name
/// the real implementation.
final incentivesRepositoryProvider = Provider<IncentivesRepository>(
  (ref) => throw UnimplementedError(
    'incentivesRepositoryProvider must be overridden in ProviderScope.',
  ),
);

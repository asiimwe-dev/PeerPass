import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';

/// The signed-in user's own certificate eligibility.
///
/// An [AsyncNotifier] because the only thing to do with it is load it, and
/// [AsyncValue] already carries the states a screen has to render: loading, the
/// answer, and the reason there isn't one.
///
/// The automatic retry is switched off for the reason `sessionListProvider`
/// switches it off: a screen that offers a "Try again" button must not also be
/// re-requesting underneath the user's finger. The button is the retry.
final certificateEligibilityProvider =
    AsyncNotifierProvider<CertificateEligibilityNotifier, CertificateEligibility>(
      CertificateEligibilityNotifier.new,
      retry: (retryCount, error) => null,
    );

class CertificateEligibilityNotifier extends AsyncNotifier<CertificateEligibility> {
  @override
  Future<CertificateEligibility> build() =>
      ref.read(incentivesRepositoryProvider).myCertificate();
}

import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';
import 'package:peerpass/features/incentives/data/repositories/incentives_repository.dart';

/// In-memory stand-in for the incentives endpoints.
///
/// Resolved by widget tests, which have no server to talk to, and seeded rather
/// than computed so a test states the numbers it wants to see on screen. The
/// eligible flag is set from the same tally the API would use, rather than being
/// a second field a test has to keep consistent with the minutes by hand.
class FakeIncentivesRepository implements IncentivesRepository {
  FakeIncentivesRepository({
    this.eligibility,
    this.failure,
    this.hasTutorProfile = true,
    this.certifiedMinutes = 0,
    this.requiredMinutes = 2400,
  });

  /// The answer to return, when the call should succeed.
  final CertificateEligibility? eligibility;

  /// The failure to throw, when the call should fail.
  final Failure? failure;

  /// Whether the fake caller is treated as having a tutor profile.
  final bool hasTutorProfile;

  /// The tally the fake builds its answer from, the way the API would.
  final int certifiedMinutes;

  /// The threshold the fake reports, so a test can state a lowered one.
  final int requiredMinutes;

  /// How many times [myCertificate] has been called.
  int calls = 0;

  @override
  Future<CertificateEligibility> myCertificate() async {
    calls++;
    final thrown = failure;
    if (thrown != null) throw thrown;
    if (eligibility != null) return eligibility!;
    return CertificateEligibility(
      hasTutorProfile: hasTutorProfile,
      eligible: certifiedMinutes >= requiredMinutes,
      certifiedMinutes: certifiedMinutes,
      requiredMinutes: requiredMinutes,
      remainingMinutes:
          (requiredMinutes - certifiedMinutes).clamp(0, requiredMinutes),
      progress: certifiedMinutes / requiredMinutes,
    );
  }
}

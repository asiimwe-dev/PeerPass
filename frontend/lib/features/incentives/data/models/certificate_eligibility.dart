import 'package:flutter/foundation.dart';

/// The signed-in tutor's standing against the certificate threshold.
///
/// A wire DTO and nothing more. Every threshold question is answered by the API
/// -- [eligible] is its verdict, not a comparison this client makes -- because a
/// client that divided [certifiedMinutes] by [requiredMinutes] itself would hold
/// a second copy of the rule and would go on showing the old one after a pilot
/// lowered it.
///
/// [requiredMinutes] and [progress] are therefore read from the response and
/// never derived. There is no 2400 in this client, and adding one would put the
/// product decision in a place nobody changes it.
@immutable
class CertificateEligibility {
  const CertificateEligibility({
    required this.hasTutorProfile,
    required this.eligible,
    required this.certifiedMinutes,
    required this.requiredMinutes,
    required this.remainingMinutes,
    required this.progress,
  });

  /// Reads the wire form.
  ///
  /// Every field is required, including the two the client could in principle
  /// work out. Defaulting them would mean recomputing the API's arithmetic on a
  /// device, and a body missing them is a contract change rather than a partial
  /// answer -- a [FormatException] the repository turns into a message, which is
  /// what a server fault should look like to a tutor.
  ///
  /// `generated_at` is deliberately not carried. It is the server's clock, and
  /// "as the server saw it" is not what a tutor needs to know; the moment this
  /// screen rendered the numbers is. It stays in the response for whoever needs
  /// it in a log.
  factory CertificateEligibility.fromJson(Map<String, dynamic> json) {
    final hasTutorProfile = json['has_tutor_profile'];
    final eligible = json['eligible'];
    final certifiedMinutes = json['certified_minutes'];
    final requiredMinutes = json['required_minutes'];
    final remainingMinutes = json['remaining_minutes'];
    final progress = json['progress'];

    if (hasTutorProfile is! bool ||
        eligible is! bool ||
        certifiedMinutes is! num ||
        requiredMinutes is! num ||
        remainingMinutes is! num ||
        progress is! num) {
      throw const FormatException(
        'certificate response was missing a required field',
      );
    }

    return CertificateEligibility(
      hasTutorProfile: hasTutorProfile,
      eligible: eligible,
      certifiedMinutes: certifiedMinutes.toInt(),
      requiredMinutes: requiredMinutes.toInt(),
      remainingMinutes: remainingMinutes.toInt(),
      progress: progress.toDouble(),
    );
  }

  /// Whether the caller has a tutor profile at all.
  ///
  /// The API's own answer rather than something the client infers from the
  /// caller's roles. A student and a brand-new tutor both read as zero minutes,
  /// and only one of them is on the path to a certificate; guessing from a role
  /// the client happens to hold would be the client deciding who is a tutor.
  final bool hasTutorProfile;

  /// Whether the threshold has been met. The API's verdict, not this client's.
  final bool eligible;

  /// Minutes that counted towards a certificate, exactly as stored.
  final int certifiedMinutes;

  /// The configured threshold, as the operator set it.
  final int requiredMinutes;

  /// Minutes still to go. Zero once [eligible].
  final int remainingMinutes;

  /// How far along, from 0.0 to 1.0, already clamped by the API.
  final double progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CertificateEligibility &&
          other.hasTutorProfile == hasTutorProfile &&
          other.eligible == eligible &&
          other.certifiedMinutes == certifiedMinutes &&
          other.requiredMinutes == requiredMinutes &&
          other.remainingMinutes == remainingMinutes &&
          other.progress == progress;

  @override
  int get hashCode => Object.hash(
    hasTutorProfile,
    eligible,
    certifiedMinutes,
    requiredMinutes,
    remainingMinutes,
    progress,
  );

  @override
  String toString() =>
      'CertificateEligibility($certifiedMinutes/$requiredMinutes, eligible: $eligible)';
}

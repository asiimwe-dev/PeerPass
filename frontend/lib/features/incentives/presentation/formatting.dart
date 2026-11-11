import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';

/// One line of the certificate checklist: what is counted, how much there is,
/// and whether that condition is already met.
typedef CertificateRequirement = ({String label, String value, bool met});

/// How many minutes read as in this app.
///
/// Hours and minutes rather than a rounded number of hours, because rounding is
/// what makes this screen lie: 2399 minutes displayed as "40 of 40h" looks
/// earned, and it is not. The shortfall is the whole reason the API reports it,
/// so the label has to carry it exactly.
///
/// Hours only when the minutes land on the hour, because "2h 0m" is noise.
String hoursAndMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

/// A rating to two decimal places.
///
/// The API sends the exact stored mean; the wire is a decimal string so no value
/// is silently rounded on the way in. Two places is the scale the database and
/// the promotion rule use, so the number the tutor reads is the number the rules
/// were applied with.
String ratingLabel(double rating) => rating.toStringAsFixed(2);

/// The headline under the bar: either the verdict or the hours tally.
String certificateProgressLabel(CertificateEligibility eligibility) {
  if (eligibility.eligible) return 'Certificate earned';
  return '${hoursAndMinutes(eligibility.certifiedMinutes)} of '
      '${hoursAndMinutes(eligibility.requiredMinutes)}';
}

/// What is still to go, or null when there is nothing left to go.
///
/// The first outstanding condition, in the order the certificate is explained:
/// hours, sessions, rating. Null rather than an empty string or a cheerful
/// "you're done" once eligible, so the caller cannot render a remaining count
/// that contradicts the verdict above it.
String? remainingLabel(CertificateEligibility eligibility) {
  if (eligibility.eligible) return null;

  if (!eligibility.minutesMet) {
    final remaining = eligibility.remainingMinutes;
    if (remaining < 60) {
      return remaining == 1 ? '1 minute to go' : '$remaining minutes to go';
    }
    return '${hoursAndMinutes(remaining)} to go';
  }

  if (!eligibility.sessionsMet) {
    final remaining = eligibility.remainingSessions;
    return remaining == 1
        ? '1 more session to go'
        : '$remaining more sessions to go';
  }

  if (!eligibility.ratingMet) {
    if (eligibility.ratingCount < eligibility.requiredSessions) {
      final remaining = eligibility.requiredSessions - eligibility.ratingCount;
      return remaining == 1
          ? '1 more rating needed'
          : '$remaining more ratings needed';
    }
    return 'Average needs to reach '
        '${ratingLabel(eligibility.requiredAverageRating)}';
  }

  // Every condition is met but the API did not call it eligible. That is a
  // server disagreement, and inventing a shortfall here would be worse than
  // saying nothing.
  return null;
}

/// The three conditions, as rows the certificate screen can draw.
///
/// The values are statements of the stored numbers and thresholds, not a second
/// calculation of the verdict: `met` is the API's answer for that condition.
List<CertificateRequirement> certificateRequirements(
  CertificateEligibility eligibility,
) {
  return [
    (
      label: 'Teaching hours',
      // "banked" and "needed" rather than "X of Y", because the headline above
      // already says "X of Y": two identical lines in one card read as a
      // rendering bug rather than as emphasis.
      value:
          '${hoursAndMinutes(eligibility.certifiedMinutes)} banked · '
          '${hoursAndMinutes(eligibility.requiredMinutes)} needed',
      met: eligibility.minutesMet,
    ),
    (
      label: 'Sessions completed',
      value:
          '${eligibility.completedSessions} of '
          '${eligibility.requiredSessions}',
      met: eligibility.sessionsMet,
    ),
    (
      label: 'Average rating',
      value: _ratingRequirementValue(eligibility),
      met: eligibility.ratingMet,
    ),
  ];
}

String _ratingRequirementValue(CertificateEligibility eligibility) {
  final average = eligibility.averageRating;
  final required = ratingLabel(eligibility.requiredAverageRating);

  if (average == null) {
    return 'No ratings yet — needs $required';
  }

  final have = ratingLabel(average);
  if (eligibility.ratingCount < eligibility.requiredSessions) {
    return '$have from ${eligibility.ratingCount} of '
        '${eligibility.requiredSessions} ratings';
  }
  if (!eligibility.ratingMet) {
    return '$have — needs $required';
  }
  return '$have over ${eligibility.ratingCount} ratings';
}

/// The bar's value, guarded against a response outside 0..1.
///
/// `LinearProgressIndicator` throws on a value above 1.0, so a server that
/// widened the scale would take the screen down rather than draw an overfull
/// bar. Clamping here is display tolerance, not a second opinion about
/// eligibility: the verdict above is the API's, unchanged.
double progressValue(CertificateEligibility eligibility) {
  if (eligibility.progress.isNaN) return 0;
  return eligibility.progress.clamp(0.0, 1.0);
}

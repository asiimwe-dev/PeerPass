import 'package:peerpass/features/incentives/data/models/certificate_eligibility.dart';

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

/// The headline under the bar: either the verdict or the tally behind it.
String certificateProgressLabel(CertificateEligibility eligibility) {
  if (eligibility.eligible) return 'Certificate earned';
  return '${hoursAndMinutes(eligibility.certifiedMinutes)} of '
      '${hoursAndMinutes(eligibility.requiredMinutes)}';
}

/// What is still to go, or null when there is nothing left to go.
///
/// Null rather than an empty string or a cheerful "you're done" once eligible,
/// so the caller cannot render a remaining count that contradicts the verdict
/// above it.
String? remainingLabel(CertificateEligibility eligibility) {
  if (eligibility.eligible) return null;
  final remaining = eligibility.remainingMinutes;
  if (remaining < 60) {
    return remaining == 1 ? '1 minute to go' : '$remaining minutes to go';
  }
  return '${hoursAndMinutes(remaining)} to go';
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

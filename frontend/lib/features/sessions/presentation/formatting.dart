import 'package:intl/intl.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';

/// When a session happens, as a student reads it.
///
/// Falls back through the three timestamps the API records, in the order that
/// tells the user most: a session that has started says so, a scheduled one gives
/// its time, and a session with neither -- the API allows `scheduled_start` to be
/// null -- is described by when it was booked rather than left blank.
///
/// The default locale is used because the app has no locale switcher and
/// `DateFormat` with no locale does not need `initializeDateFormatting`, which
/// would mean shipping locale data for a case that does not exist.
String sessionWhenLabel(SessionModel session) {
  final moment = session.startedAt ?? session.scheduledStart;
  if (moment != null) return momentLabel(moment.toLocal());

  return 'Booked ${momentLabel(session.createdAt.toLocal())}';
}

/// One instant, as a user reads it.
String momentLabel(DateTime moment) => _formatMoment(moment.toLocal());

/// How long a session is, as a user reads it.
///
/// An hour and a half is "1 hr 30 min" rather than "90 min": the number the API
/// stores is a record of elapsed time, not something a student would say out loud.
String durationLabel(int minutes) {
  if (minutes <= 0) return 'Not recorded';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (remainder == 0) return '$hours hr';
  return '$hours hr $remainder min';
}

String _formatMoment(DateTime moment) =>
    DateFormat('EEE d MMM, HH:mm').format(moment);

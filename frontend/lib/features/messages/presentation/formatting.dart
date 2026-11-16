import 'package:intl/intl.dart';

/// When a message was sent, as the reader says it out loud.
///
/// The granularity changes with distance: today's messages only need a clock,
/// yesterday's need the word, and anything older needs the date. A chat that
/// printed a full date under every line would be noise, and one that printed only
/// a clock would make last week's venue look like a plan for tonight.
String messageTimeLabel(DateTime createdAt, {DateTime? now}) {
  final moment = createdAt.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();

  if (_isSameDay(moment, reference)) {
    return DateFormat('HH:mm').format(moment);
  }
  if (_isSameDay(moment, reference.subtract(const Duration(days: 1)))) {
    return 'Yesterday ${DateFormat('HH:mm').format(moment)}';
  }
  if (moment.year == reference.year) {
    return DateFormat('d MMM, HH:mm').format(moment);
  }
  return DateFormat('d MMM yyyy, HH:mm').format(moment);
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

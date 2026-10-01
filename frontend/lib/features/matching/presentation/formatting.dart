import 'package:peerpass/features/matching/data/models/match_result.dart';

/// Why a widened search came back wider than the question.
///
/// The sentence a student reads when the exact unit had nobody eligible and the
/// API searched the subject instead. Built as a function of the unit's name
/// because a notice that says "the wider subject" without saying which one leaves
/// the student unable to tell whether it widened at all.
///
/// Parameterised on the unit rather than hardcoded to the courses the pilot
/// happens to run: the API decides what a subject is, and this only reports it.
String widenedNotice(String unitLabel) =>
    'Nobody teaches $unitLabel itself right now, so these are tutors from the '
    'wider subject. Ask them whether they can help with this unit before you '
    'book.';

/// The reason no tutor was proposed, as a sentence for the empty state.
///
/// Distinct from a failure on purpose: nobody being eligible is a fact about the
/// platform that the exclusions below it usually explain, and rendering it as an
/// error would tell a student something is broken when the search worked.
String noEligibleTutorsCopy(String unitLabel) =>
    'No tutor is eligible for $unitLabel yet. The reasons below say who was '
    'considered and why they were not proposed.';

/// The exclusions as sentences, one line per distinct reason.
///
/// The API sends a tutor id and a code and nothing else, so a line cannot name
/// the tutor. Grouping by code is therefore the only way to say anything useful:
/// three tutors passed over for one reason is one sentence, and three reasons
/// are three lines. A code this client does not know gets its own line saying so,
/// rather than being dropped -- an exclusion the student cannot see is the
/// failure `MatchExclusion` exists to prevent.
List<String> exclusionLines(List<MatchExclusion> exclusions) {
  final counts = <MatchExclusionReason?, int>{};
  for (final exclusion in exclusions) {
    counts[exclusion.reason] = (counts[exclusion.reason] ?? 0) + 1;
  }

  return [
    for (final entry in counts.entries)
      '${_subject(entry.value)} ${_explanation(entry.key)}',
  ];
}

String _explanation(MatchExclusionReason? reason) =>
    reason?.explanation ?? 'we could not say why they were left out';

/// The subject of the sentence, agreeing with the count.
String _subject(int count) {
  if (count <= 0) return 'Nobody';
  if (count == 1) return 'One tutor was not proposed because';
  return '$count tutors were not proposed because';
}

/// The action on a candidate tile.
///
/// Stated as a question the student can refuse rather than an invitation they can
/// only accept. Choosing a tutor is the one thing in this screen that changes
/// another person's work queue, and "Ask them to tutor you" is the version of
/// that a student can see they are about to send it.
String askTutorCopy(String tutorName) => 'Ask $tutorName to tutor you';

/// The tile's own label when the request has already gone to this tutor.
///
/// Not a second button and not a disabled one: the action is done, and a
/// control that still looks pressable on a completed request is how a student
/// ends up asking twice for the same thing.
String tutorChosenCopy(String tutorName) => 'Asked $tutorName';

/// The waiting state, once a tutor has been named.
///
/// Says "asked" and not "booked", and says what the student can do about it,
/// because `pending_confirmation` is the platform holding a question open for
/// somebody who has not answered it yet. A student told they are booked here
/// would turn up to a session nobody agreed to.
String awaitingTutorCopy(String tutorName) =>
    'Asked $tutorName. They have not confirmed yet, so there is no session '
    'booked. Pull down to check whether they have answered.';

/// The state after the chosen tutor said no.
///
/// Names the outcome rather than leaving the student to infer it from an empty
/// list, and says what to do instead, because a declined request is final and
/// "try again" against this one would be refused by the API.
String declinedCopy(String topic) =>
    'Your chosen tutor turned down "$topic". You can ask for help with it '
    'again as a new request.';

/// Why a choice could not be sent, as the student's own next step.
///
/// Built beside the repository's own failure message rather than restating it:
/// the repository already decided the wording once, for every screen, and a
/// second phrasing here is the place where the two drift and the student is told
/// something different from what the server said.
String choiceFailureHint(String tutorName) =>
    'Your request was not sent, so $tutorName has not been asked. '
    'Nothing has changed and you can try again.';

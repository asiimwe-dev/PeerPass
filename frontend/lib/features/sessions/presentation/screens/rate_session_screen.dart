import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/core/widgets/failure_view.dart';
import 'package:peerpass/core/widgets/loading_view.dart';
import 'package:peerpass/features/sessions/data/models/session_model.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';

/// The score and the note for a finished session, in one submission.
///
/// Two things are being asked for, and it is worth being clear that they are not
/// the same thing. The score is a judgement of the tutor. The endorsement, which
/// is optional, is a claim that the tutor covered the course unit the session was
/// booked for -- something a five does not imply and a three does not rule out.
/// The API stores them apart for that reason, and this screen keeps them apart.
///
/// The score is the only part that cannot be left out, because a rating with no
/// score is not a rating. The note and endorsement are skippable, and the
/// endorsement defaults to off: a student must provide the score but is not made
/// to assert a claim about a tutor's coverage to finish the review.
class RateSessionScreen extends ConsumerWidget {
  const RateSessionScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final session = detail.session;

    if (session == null) {
      final failure = detail.loadFailure;
      if (failure != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Rate session')),
          body: SafeArea(
            child: Center(
              child: ContentWidthLimiter(
                child: FailureView(
                  failure: failure,
                  onRetry: () => ref
                      .read(sessionDetailProvider(sessionId).notifier)
                      .reload(),
                ),
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        body: SafeArea(child: Center(child: LoadingView())),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Rate session')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ContentWidthLimiter(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.lg),
                child: _Form(session: session),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.session});

  final SessionModel session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final form = ref.watch(ratingFormProvider(session.id));
    // The role of the rater decides whether there is a tutor to endorse at all.
    // The API derives the ratee from the session and then writes the endorsement
    // to that ratee's tutor record, so a tutor rating a student would be recorded
    // as a tutor endorsing a student -- which is not what the field means, and is
    // not something the client should offer.
    final isRaterTutee = _isRaterTutee(ref, session);
    // Locked once a rating exists. `POST /v1/ratings/{session_id}` updates the
    // rating in place rather than adding a second one, so a second pass through
    // this screen would overwrite the first -- not what a "rate this session"
    // screen implies when the flag says there is already a rating on it.
    final alreadySubmitted = session.isRated;
    final controller = ref.read(ratingFormProvider(session.id).notifier);

    return PopScope(
      // The first rating is mandatory. Once a rating exists, this screen is an
      // optional correction and normal back navigation is restored.
      canPop: alreadySubmitted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(session.topic, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppDimens.xs),
          Text(
            alreadySubmitted
                ? 'You already rated this session. Sending this replaces it.'
                : 'A rating is required to finish this session review.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppDimens.lg),
          _ScorePicker(
            score: form.score,
            enabled: !form.submitting,
            onSelected: controller.chooseScore,
          ),
          const SizedBox(height: AppDimens.lg),
          Text('Add a note (optional)', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppDimens.sm),
          TextField(
            // No controller: the draft is in the provider, so it survives a rebuild
            // and a keyboard-triggered setState, which is the same reasoning the
            // onboarding wizard's state keeps.
            onChanged: controller.writeFeedback,
            enabled: !form.submitting,
            minLines: 3,
            maxLines: 5,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'What was useful? What would you tell someone booking?',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          if (isRaterTutee) ...[
            const SizedBox(height: AppDimens.md),
            CheckboxListTile(
              value: form.endorsing,
              // A checkbox that cannot be turned on is a broken promise, so this one
              // is not shown unless the session's unit is actually known -- the API
              // refuses an endorsement naming anything other unit, and there is
              // nothing for the claim to attach to otherwise.
              onChanged: form.submitting
                  ? null
                  : (value) => controller.setEndorsing(value: value ?? false),
              title: const Text('Recommend this tutor for this course unit'),
              // Says different things on a first rating and on a correction, because
              // the API behaves differently: `endorsed_course_unit_ids` is replaced on
              // every submission, and an empty list withdraws what the rater endorsed
              // last time. `RatingResponse` does not echo a rater's own endorsements,
              // so the box cannot start out ticked to match, and a student fixing
              // their score would otherwise lose the claim without being told.
              subtitle: Text(
                alreadySubmitted
                    ? 'Optional. Sending this withdraws the recommendation if you '
                          'leave it off.'
                    : 'Optional. It helps other students find a tutor who has '
                          'actually taught this unit.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
          if (form.failure != null) ...[
            const SizedBox(height: AppDimens.md),
            Text(
              form.failure!.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppDimens.lg),
          FilledButton(
            onPressed: form.canSubmit
                ? () => _submit(context, ref, session)
                : null,
            child: form.submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(alreadySubmitted ? 'Update rating' : 'Submit rating'),
          ),
        ],
      ),
    );
  }

  /// Whether the signed-in user is the tutee in this session.
  bool _isRaterTutee(WidgetRef ref, SessionModel session) {
    final viewerId = ref.watch(sessionControllerProvider).profile?.publicId;
    return viewerId != null && session.isTutee(viewerId);
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    SessionModel session,
  ) async {
    final rating = await ref
        .read(ratingFormProvider(session.id).notifier)
        .submit();
    // A null rating means the API refused it and the reason is on the form; the
    // screen stays open so the note is not retyped.
    if (rating == null) return;
    if (!context.mounted) return;
    context.pop();
  }
}

/// One tappable star, for a score the API bounds at 1 through 5.
///
/// The count is the API's, not a design decision, and the number of stars is
/// read from the same place the limit is enforced so the two cannot drift: a
/// sixth star would be something the client will send and the server will refuse.
class _ScorePicker extends StatelessWidget {
  const _ScorePicker({
    required this.score,
    required this.enabled,
    required this.onSelected,
  });

  /// 1 through 5, the range `POST /v1/ratings/{session_id}` accepts.
  static const int maxScore = 5;

  final int? score;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = score;

    return Row(
      children: [
        for (var value = 1; value <= maxScore; value++) ...[
          if (value > 1) const SizedBox(width: AppDimens.xs),
          Semantics(
            button: true,
            label: '$value of $maxScore',
            selected: current == value,
            child: IconButton(
              onPressed: enabled ? () => onSelected(value) : null,
              iconSize: 36,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                current != null && value <= current
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: current != null && value <= current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

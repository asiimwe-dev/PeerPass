import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/widgets/content_width_limiter.dart';
import 'package:peerpass/features/sessions/presentation/providers/session_providers.dart';

/// Turning "yes, I will take this" into a session.
///
/// The tutor's half of a choice the student made. The student already wrote the
/// question and already named this tutor; what is left to agree is how long the
/// session is meant to be, and that is the only thing this screen asks for.
/// Restating the topic or the course unit would be asking the tutor to confirm
/// the student's words back to them, and the API checks the unit against the
/// request anyway.
///
/// The route carries the request's own values rather than this screen fetching
/// them, and that is a deliberate trade. The alternative -- the sessions feature
/// reading `/v1/matching/help-requests/awaiting-me` to recover what the matching
/// feature already had on screen -- would make one feature own two features'
/// endpoints and put the tutor's decision behind a fetch that can fail for a
/// reason that has nothing to do with the answer. What the session is then titled
/// with comes from the request, so there is no second place for it to be edited.
///
/// The navigation target after a successful confirmation is the new session, not
/// the list: the tutor just agreed to something specific and the useful next
/// screen is the thing they agreed to. Its PIN is what lets them start it.
class ConfirmRequestScreen extends ConsumerStatefulWidget {
  const ConfirmRequestScreen({
    required this.requestId,
    required this.courseUnitId,
    required this.topic,
    super.key,
  });

  /// The help request being confirmed.
  final String requestId;

  /// The unit the request is for, checked by the API against the request itself.
  final String courseUnitId;

  /// The student's question, as the request carries it.
  final String topic;

  @override
  ConsumerState<ConfirmRequestScreen> createState() =>
      _ConfirmRequestScreenState();
}

class _ConfirmRequestScreenState extends ConsumerState<ConfirmRequestScreen> {
  /// Holds the text in the field, seeded from the provider.
  ///
  /// Both, and the reason is that each covers a loss the other cannot. The
  /// controller is what puts a stored draft back into an empty field on the way
  /// back to this route, because [TextField] takes its value from a controller
  /// and has no initial value of its own -- a provider holding the draft and
  /// nothing reading it back leaves the field blank every time. The provider is
  /// what survives the field being disposed at all, which a controller does not:
  /// popping this route destroys the state, and the Android back gesture is one
  /// swipe away.
  late final TextEditingController _duration;

  @override
  void initState() {
    super.initState();
    _duration = TextEditingController(
      text: ref.read(confirmRequestProvider(widget.requestId)).durationMinutes,
    );
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  String get requestId => widget.requestId;

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(confirmRequestProvider(requestId));
    final controller = ref.read(confirmRequestProvider(requestId).notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm this session')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ContentWidthLimiter(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.topic, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppDimens.xs),
                    Text(
                      'Confirming books the session and sends the student your '
                      'PIN. The student sees that you have answered.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppDimens.lg),
                    Text(
                      'How long, in minutes?',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppDimens.sm),
                    TextField(
                      controller: _duration,
                      onChanged: controller.writeDuration,
                      enabled: !form.submitting,
                      keyboardType: TextInputType.number,
                      // Numeric input rather than a field the tutor has to trust:
                      // a pasted "60 mins" or a stray space is refused by the
                      // button below instead of being silently coerced into a
                      // session half the length.
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '60',
                        border: OutlineInputBorder(),
                        suffixText: 'minutes',
                      ),
                    ),
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
                      onPressed: form.canSubmit ? _confirm : null,
                      child: form.submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirm'),
                    ),
                    const SizedBox(height: AppDimens.sm),
                    TextButton(
                      onPressed: form.submitting
                          ? null
                          : () => context.pop(),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final created = await ref
        .read(confirmRequestProvider(requestId).notifier)
        .submit(courseUnitId: widget.courseUnitId, topic: widget.topic);
    // Null means the API refused it and the reason is on the form; the screen
    // stays open so the length is not retyped.
    if (created == null || !mounted) return;
    // `go` rather than `push`: the request has been consumed, so going back to
    // this form would offer a confirmation the API will refuse, and a refusal is
    // a worse answer than never having let the tutor try. The session is where the
    // PIN is, and the PIN is what starts the session they just agreed to.
    context.go(AppRoutes.sessionDetailPath(created.id));
  }
}

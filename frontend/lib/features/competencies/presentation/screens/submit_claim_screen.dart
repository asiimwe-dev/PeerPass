import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/models/academic_fallback.dart';
import 'package:peerpass/core/models/course_unit_option.dart';
import 'package:peerpass/core/models/grade_option.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/repositories/auth_repository.dart';
import 'package:peerpass/features/competencies/data/repositories/competencies_repository.dart';
import 'package:peerpass/features/competencies/presentation/providers/competency_providers.dart';

/// Submits proof of a grade for one course unit.
///
/// Named for what it does rather than what it promises. The old name, "become a
/// tutor", described an outcome: submitting this form does not make anyone a
/// tutor. It records a claim that an operator then reviews, and the tutor role is
/// granted by that review. A screen whose title says "Become a tutor" also
/// invites the reading that the grade gate is the client's to apply, which is
/// exactly the rule the API owns.
class SubmitClaimScreen extends ConsumerStatefulWidget {
  const SubmitClaimScreen({super.key});

  @override
  ConsumerState<SubmitClaimScreen> createState() => _SubmitClaimScreenState();
}

class _SubmitClaimScreenState extends ConsumerState<SubmitClaimScreen> {
  final TextEditingController _evidenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _source = 'transcript';
  String? _courseUnitId;
  String? _gradeId;
  bool _submitting = false;

  @override
  void dispose() {
    _evidenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(sessionControllerProvider).profile;
    final universityId = profile?.universityId ?? '';
    final facultyId = profile?.facultyId;
    final claimScope = (universityId: universityId, facultyId: facultyId);
    final courseUnitsAsync = ref.watch(claimCourseUnitsProvider(claimScope));
    final gradesAsync = ref.watch(claimGradesProvider(universityId));
    final isMustAsync = ref.watch(isMustUniversityProvider(universityId));
    final claimsAsync = ref.watch(myClaimsProvider);
    final limitsAsync = ref.watch(applicationLimitsProvider);

    final courseUnits = courseUnitsAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <CourseUnitOption>[],
    );

    // A unit with a pending or verified claim is not an option: the API refuses
    // it, so offering it would send a tutor into a form that can only fail. A
    // rejected claim is deliberately left in, because answering a rejection is
    // exactly what this form is for.
    final liveUnitIds = claimsAsync.maybeWhen(
      data: (items) => {
        for (final claim in items)
          if (claim.isLive) claim.courseUnitId,
      },
      orElse: () => const <String>{},
    );
    final availableUnits = [
      for (final unit in courseUnits)
        if (!liveUnitIds.contains(unit.publicId)) unit,
    ];
    final limits = limitsAsync.value;
    final atCap = limits?.atCap ?? false;
    final liveGrades = gradesAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <GradeOption>[],
    );
    final isMust = isMustAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );
    // `claimGradesProvider` already substitutes the saved MUST scale when the
    // live catalogue is empty, so this is the list to render. The `isMust` flag
    // is now only about what to *say*: whether to admit the grades shown are a
    // fallback rather than the university's own.
    final grades = liveGrades;

    // The default is the first unit the tutor has not already claimed. Keeping a
    // selection that claims filtered out would leave the dropdown pointing at a
    // row it no longer renders, which reads as a broken form.
    if (_courseUnitId == null ||
        !availableUnits.any((unit) => unit.publicId == _courseUnitId)) {
      _courseUnitId = availableUnits.isEmpty
          ? null
          : availableUnits.first.publicId;
    }
    if (liveGrades.isNotEmpty && isMustFallbackGrade(_gradeId)) {
      _gradeId = null;
    }

    final canSubmit =
        !_submitting &&
        !atCap &&
        profile != null &&
        profile.universityId != null &&
        profile.facultyId != null &&
        availableUnits.any((unit) => unit.publicId == _courseUnitId) &&
        _courseUnitId != null &&
        _gradeId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tutor verification')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(claimCourseUnitsProvider(claimScope))
              ..invalidate(claimGradesProvider(universityId))
              ..invalidate(isMustUniversityProvider(universityId))
              ..invalidate(myClaimsProvider)
              ..invalidate(applicationLimitsProvider);
            await Future.wait([
              ref.read(claimCourseUnitsProvider(claimScope).future),
              ref.read(claimGradesProvider(universityId).future),
              ref.read(myClaimsProvider.future),
              ref.read(applicationLimitsProvider.future),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimens.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Submit your academic proof',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppDimens.md),
                Text(
                  'A verified grade makes you eligible for tutoring requests once it is reviewed.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppDimens.xl),
                if (profile == null || profile.universityId == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppDimens.lg),
                      child: Text(
                        'Complete your profile before submitting tutor proof.',
                      ),
                    ),
                  )
                else ...[
                  // The cap is the server's, so it is explained before a tutor
                  // fills in a form rather than after the API refuses it. The
                  // form stays visible below with its button disabled, so the
                  // reason and the control are on the same screen.
                  if (limits != null && atCap) ...[
                    _NoticeCard(
                      icon: Icons.lock_clock_outlined,
                      title: 'Application limit reached',
                      message:
                          'You are holding ${limits.activeCount} of '
                          '${limits.maxActiveCourseUnits} active course '
                          'applications. Wait for a reviewer to decide one '
                          'before applying for another course.',
                    ),
                    const SizedBox(height: AppDimens.md),
                  ] else if (availableUnits.isEmpty &&
                      liveUnitIds.isNotEmpty) ...[
                    // A faculty can publish fewer units than the cap. Saying so
                    // is the difference between "nothing left to apply for" and
                    // a dropdown that silently has no options.
                    const _NoticeCard(
                      icon: Icons.checklist_rounded,
                      title: 'Every course is already claimed',
                      message:
                          'You have an application in for every course in your '
                          'faculty. You can apply again if one is not accepted.',
                    ),
                    const SizedBox(height: AppDimens.md),
                  ],
                  _buildDropdown<String>(
                    label: 'Course unit',
                    value:
                        availableUnits.any(
                          (unit) => unit.publicId == _courseUnitId,
                        )
                        ? _courseUnitId
                        : null,
                    items: [
                      for (final unit in availableUnits)
                        DropdownMenuItem(
                          value: unit.publicId,
                          child: Text('${unit.code} · ${unit.name}'),
                        ),
                    ],
                    onChanged: availableUnits.isEmpty || atCap
                        ? null
                        : (value) => setState(() => _courseUnitId = value),
                  ),
                  if (liveUnitIds.isNotEmpty && availableUnits.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.sm),
                    Text(
                      'Courses you already have an application for are not listed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppDimens.md),
                  _buildDropdown<String>(
                    label: 'Grade',
                    value: _gradeId,
                    hint: 'Select grade',
                    items: [
                      const DropdownMenuItem<String>(
                        child: Text('Select grade'),
                      ),
                      for (final grade in grades)
                        DropdownMenuItem(
                          value: grade.publicId,
                          child: Text(
                            '${grade.label} (${grade.gradePoints.toStringAsFixed(1)})',
                          ),
                        ),
                    ],
                    onChanged: grades.isEmpty
                        ? null
                        : (value) => setState(() => _gradeId = value),
                  ),
                  if (isMust && grades.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.sm),
                    Text(
                      'Showing the saved MUST grading scale while we refresh the catalogue.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppDimens.md),
                  _buildDropdown<String>(
                    label: 'Evidence source',
                    value: _source,
                    items: const [
                      DropdownMenuItem(
                        value: 'transcript',
                        child: Text('Transcript'),
                      ),
                      DropdownMenuItem(
                        value: 'portfolio',
                        child: Text('Portfolio'),
                      ),
                      DropdownMenuItem(
                        value: 'manual',
                        child: Text('Manual record'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _source = value ?? 'transcript'),
                  ),
                  const SizedBox(height: AppDimens.sm),
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimens.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                          const SizedBox(width: AppDimens.sm),
                          Expanded(
                            child: Text(
                              _source == 'transcript'
                                  ? 'An FCI operator reviews your transcript reference through the approved faculty process. Your claim stays pending until it is checked.'
                                  : 'Provide a link or reference an operator can check. Submission does not grant tutor access until review is complete.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.md),
                  TextFormField(
                    controller: _evidenceController,
                    decoration: const InputDecoration(
                      labelText: 'Evidence reference or link',
                      hintText: 'https://... or transcript reference',
                    ),
                  ),
                  const SizedBox(height: AppDimens.md),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes for the reviewer',
                      hintText: 'Optional context for faculty review',
                    ),
                  ),
                  const SizedBox(height: AppDimens.xl),
                  FilledButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: const Icon(Icons.send_outlined),
                    label: _submitting
                        ? Semantics(
                            label: 'Submitting tutor proof',
                            child: const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Text('Submit proof'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final profile = ref.read(sessionControllerProvider).profile;
    final universityId = profile?.universityId;
    if (profile == null ||
        universityId == null ||
        _courseUnitId == null ||
        _gradeId == null) {
      return;
    }

    setState(() => _submitting = true);

    try {
      var gradeId = _gradeId!;
      if (isMustFallbackGrade(gradeId)) {
        final liveGrades = await ref
            .read(authRepositoryProvider)
            .grades(universityId: universityId);
        final fallback = mustFallbackGrades.firstWhere(
          (grade) => grade.publicId == gradeId,
        );
        final resolved = liveGrades.where(
          (grade) =>
              grade.label == fallback.label &&
              grade.gradePoints == fallback.gradePoints,
        );
        if (resolved.isEmpty) {
          throw StateError(
            'The MUST grading catalogue is unavailable. Please retry and try again.',
          );
        }
        gradeId = resolved.first.publicId;
      }

      final failure = await ref
          .read(submitClaimProvider)
          .submit(
            courseUnitId: _courseUnitId!,
            gradeId: gradeId,
            source: _source,
            evidenceReference: _evidenceController.text.trim().isEmpty
                ? null
                : _evidenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (!mounted) return;
      if (failure != null) {
        // The controller returns the failure rather than throwing, so this branch
        // and the success one are visibly different: a refusal keeps the tutor on
        // the form with their answers intact, which matters because the two
        // refusals they can hit are a duplicate claim and a lost connection, and
        // neither is fixed by retyping.
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your tutor proof was submitted and is awaiting review.',
          ),
        ),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    String? hint,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey(label),
      initialValue: value,
      decoration: InputDecoration(labelText: label, hintText: hint),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// A plain explanation, shown when the form cannot be used as it stands.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: AppDimens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppDimens.xxs),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

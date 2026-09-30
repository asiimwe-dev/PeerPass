import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/data/datasources/remote_academics_datasource.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';

class BecomeTutorScreen extends ConsumerStatefulWidget {
  const BecomeTutorScreen({super.key});

  @override
  ConsumerState<BecomeTutorScreen> createState() => _BecomeTutorScreenState();
}

class _BecomeTutorScreenState extends ConsumerState<BecomeTutorScreen> {
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
    final courseUnitsAsync = ref.watch(courseUnitsProvider(universityId));
    final gradesAsync = ref.watch(gradesProvider(universityId));

    final courseUnits = courseUnitsAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <CourseUnitOption>[],
    );
    final grades = gradesAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <GradeOption>[],
    );

    if (_courseUnitId == null && courseUnits.isNotEmpty) {
      _courseUnitId = courseUnits.first.publicId;
    }
    if (_gradeId == null && grades.isNotEmpty) {
      _gradeId = grades.first.publicId;
    }

    final canSubmit = !_submitting &&
        profile != null &&
        profile.universityId != null &&
        _courseUnitId != null &&
        _gradeId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Become a tutor')),
      body: SafeArea(
        child: SingleChildScrollView(
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
                _buildDropdown<String>(
                  label: 'Course unit',
                  value: _courseUnitId ?? (courseUnits.isEmpty ? null : courseUnits.first.publicId),
                  items: [
                    for (final unit in courseUnits)
                      DropdownMenuItem(
                        value: unit.publicId,
                        child: Text('${unit.code} · ${unit.name}'),
                      ),
                  ],
                  onChanged: courseUnits.isEmpty
                      ? null
                      : (value) => setState(() => _courseUnitId = value),
                ),
                const SizedBox(height: AppDimens.md),
                _buildDropdown<String>(
                  label: 'Grade',
                  value: _gradeId ?? (grades.isEmpty ? null : grades.first.publicId),
                  items: [
                    for (final grade in grades)
                      DropdownMenuItem(
                        value: grade.publicId,
                        child: Text('${grade.label} (${grade.gradePoints.toStringAsFixed(1)})'),
                      ),
                  ],
                  onChanged: grades.isEmpty
                      ? null
                      : (value) => setState(() => _gradeId = value),
                ),
                const SizedBox(height: AppDimens.md),
                _buildDropdown<String>(
                  label: 'Evidence source',
                  value: _source,
                  items: const [
                    DropdownMenuItem(value: 'transcript', child: Text('Transcript')),
                    DropdownMenuItem(value: 'portfolio', child: Text('Portfolio')),
                    DropdownMenuItem(value: 'manual', child: Text('Manual record')),
                  ],
                  onChanged: (value) => setState(() => _source = value ?? 'transcript'),
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit proof'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final profile = ref.read(sessionControllerProvider).profile;
    final universityId = profile?.universityId;
    if (profile == null || universityId == null || _courseUnitId == null || _gradeId == null) {
      return;
    }

    setState(() => _submitting = true);

    try {
      await ref.read(authControllerProvider).submitTutorProof(
        courseUnitId: _courseUnitId!,
        gradeId: _gradeId!,
        source: _source,
        evidenceReference: _evidenceController.text.trim().isEmpty
            ? null
            : _evidenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your tutor proof was submitted and is awaiting review.'),
        ),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey(label),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }
}

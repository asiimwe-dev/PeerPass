import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Repository root of the `frontend` package.
///
/// `flutter test` runs with the package directory as the working directory.
final Directory _packageRoot = Directory.current;

List<File> _dartFilesIn(String relativePath) {
  final directory = Directory('${_packageRoot.path}/$relativePath');
  if (!directory.existsSync()) return const [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('dependency direction', () {
    test('core never imports from a feature', () {
      final offenders = <String>[];

      for (final file in _dartFilesIn('lib/core')) {
        final imports = file.readAsLinesSync().where((line) {
          final trimmed = line.trim();
          return trimmed.startsWith('import') && trimmed.contains('features/');
        });
        for (final import in imports) {
          offenders.add('${file.path}: $import');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'core/ must not depend on features/. Found:\n'
            '${offenders.join('\n')}',
      );
    });

    test('a feature does not import another feature presentation layer', () {
      final offenders = <String>[];

      for (final file in _dartFilesIn('lib/features')) {
        final lines = file.readAsLinesSync();
        // The first import in a file names the feature that owns it.
        final owner = _owningFeature(file.path);
        for (final line in lines) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('import') || !trimmed.contains('features/')) {
            continue;
          }
          final target = _importedFeature(trimmed);
          // Importing another feature's *data* layer is the sanctioned way to
          // reuse it, so only presentation is an offence. The previous version
          // rejected every cross-feature import while its own failure message
          // described a presentation-only rule, which meant the guide's one
          // permitted dependency -- the owning feature's repository contract --
          // was untestable in practice.
          if (target != null && target != owner && trimmed.contains('/presentation/')) {
            offenders.add('${file.path} imports $target/presentation');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            "Cross-feature access must go through the owning feature's "
            'data/repositories/ contract. Found:\n${offenders.join('\n')}',
      );
    });

    test('a feature reaches another feature only through its data layer', () {
      // The flip side of the rule above, and the reason the layer is split at
      // all. A cross-feature import that lands in data/ is allowed, but it has to
      // land in data/ -- not in a shared/ dumping ground, and not in core.
      final offenders = <String>[];

      for (final file in _dartFilesIn('lib/features')) {
        final lines = file.readAsLinesSync();
        final owner = _owningFeature(file.path);
        for (final line in lines) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('import') || !trimmed.contains('features/')) {
            continue;
          }
          final target = _importedFeature(trimmed);
          if (target == null || target == owner) continue;
          final isDataLayer = trimmed.contains('/data/');
          final isOwnContract =
              trimmed.contains('/data/repositories/auth_repository.dart');
          if (!isDataLayer || !isOwnContract) {
            offenders.add('${file.path} imports $target outside its contract');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'The only cross-feature import permitted today is another '
            "feature's repository contract, so that reuse goes through an "
            'interface rather than a screen. Found:\n${offenders.join('\n')}',
      );
    });
  });

  group('package layout', () {
    test('core exposes no shared/ directory', () {
      expect(
        Directory('${_packageRoot.path}/lib/core/shared').existsSync(),
        isFalse,
        reason: 'Shared types belong in core/models/, not a core/shared/ dump.',
      );
    });

    test('no feature defines a domain layer', () {
      final offenders = _dartFilesIn('lib/features')
          .where((file) => file.path.contains('/domain/'))
          .map((file) => file.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Matching, validation, grade, and rating rules are owned by '
            'the API, so a client-side domain layer would hold pass-through '
            'types with no logic in it.',
      );
    });
  });
}

String? _owningFeature(String path) {
  final match = RegExp('lib/features/([^/]+)/').firstMatch(path);
  return match?.group(1);
}

String? _importedFeature(String importLine) {
  final match = RegExp('features/([^/]+)/').firstMatch(importLine);
  return match?.group(1);
}

import 'package:flutter/material.dart';

import 'package:peerpass/core/constants/app_dimens.dart';

/// The app's light and dark [ThemeData].
///
/// The palette is provisional. The pilot has not settled on brand colours, so
/// this uses a single seed and lets Material 3 derive the rest, which keeps
/// contrast, focus, and container tones correct by construction. When a brand
/// palette arrives, only [seed] and the few explicit overrides need to change.
///
/// Light mode is the default because the pilot targets daytime use on shared
/// and low-cost handsets, where a dark theme buys little and costs battery on
/// OLED panels.
abstract final class AppTheme {
  /// Provisional brand seed. Confirm before the pilot ships.
  static const Color seed = Color(0xFF00695C);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Density is a deliberate low-bandwidth choice: the interface is text and
      // icons, so platform-dependent metrics would only add assets.
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        // A per-field error message needs room, so the label is allowed to sit
        // above the field rather than floating inside a fixed box.
        helperMaxLines: 2,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppDimens.screenPadding,
        ),
      ),
    );
  }
}

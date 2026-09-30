---
name: flutter-design-system
description: Enforces the Custom Atomic Design Token System for all Flutter UI implementation.
---

# Ulearn Flutter Design System (Custom Tokens)

This skill dictates how all UI components and screens must be built in the Ulearn Flutter application. We are using a **Custom Atomic Design System** with Design Tokens, avoiding raw Material defaults to maintain a strict, branded, and platform-agnostic look.

## Core Principles

1. **No Hardcoded Styles in UI:** 
   Never hardcode colors, padding, spacing, or typography directly in a widget. 
   **BAD:** `Padding(padding: EdgeInsets.all(16.0))`
   **GOOD:** `Padding(padding: EdgeInsets.all(AppSpacing.md))`

2. **Use Design Tokens:**
   All stylistic values must be sourced from the central design token classes (e.g., `AppColors`, `AppSpacing`, `AppTypography`).
   These tokens should be injected via `ThemeExtension` to integrate cleanly with `Theme.of(context)`.

3. **Atomic Components Over Material Defaults:**
   Do not use raw Material widgets like `ElevatedButton` or `TextField` directly in screens. 
   Instead, create primitive wrappers (Atoms) in `core/widgets/` (e.g., `UlearnButton`, `UlearnTextField`) and use those universally. This ensures a single source of truth for the brand's look and feel.

4. **Clean, Minimalist Aesthetic:**
   - **Colors:** Use a neutral background (white/off-white) with one primary accent color for actions. Keep contrast high.
   - **Borders & Shadows:** Prefer subtle, crisp borders over heavy drop shadows. Keep border radii consistent (e.g., `AppSpacing.radiusSm`).
   - **Typography:** Ensure readability first. Use consistent heading and body text styles.

5. **Responsive & Adaptive:**
   Ensure components flex correctly across different screen sizes (mobile-first, but robust enough for tablets). Use `LayoutBuilder` or `Flexible`/`Expanded` to prevent hard overflow constraints.

## Implementation Workflow

When building a new screen:
1. Identify required UI primitives (buttons, inputs, cards).
2. Check if an `core/widgets/` atom exists. If not, build the atom first using the Design Tokens.
3. Assemble the screen using these atoms.
4. Separate UI from state using Riverpod (UI only emits intents and listens to providers).

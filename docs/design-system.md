# PeerPass Design System

**Direction:** Campus Energy. Warm, confident, student-first.  
**Status:** Implemented in `frontend/lib/core/theme/` and `frontend/lib/core/widgets/`.

Reference screens live in [`docs/design/mockups/`](./design/mockups/). They are
design targets, not screenshots of the app.

**Migration status:** the tokens, theme, and shared components below are in
place. Screens are moved onto them one feature at a time, so a screen that has
not been visited yet may still show the previous spacing and blue palette. New
work starts from the components in section 7 and does not add new colours or
type sizes.

---

## 1. Product promise

> **Stuck → talking to the right tutor in under a minute.**

PeerPass is the friend who already passed the course, not a university portal.
Every screen is judged against that sentence.

## 2. Voice

- Short sentences. Second person. No system words.
- Retired from the interface: *eligible*, *standing*, *endorsement*,
  *handshake*, *widen to subject*, *provisional*.
- Preferred: *Verified*, *helped 12 students*, *knows Database Programming*,
  *replied in 15 min*.
- An error says what happened and what to do next. It never shows an exception.
- An empty state says what would fill it, not that something is wrong.
- Never more than one sentence of helper text under a control.

## 3. Colour

The palette is deliberately small. Colour carries meaning, not decoration.

| Token | Hex | Meaning |
| --- | --- | --- |
| `ink` | `#14142B` | Primary text, dark surfaces |
| `indigo` | `#2D2A8C` | Primary action, active navigation, trust |
| `amber` | `#FFB020` | The main CTA, progress, "this is the thing to press" |
| `coral` | `#E8503F` | Live sessions, urgency, destructive actions |
| `mint` | `#18A77E` | Verified, success, completion |
| `cream` | `#FFF9F2` | App background |
| `white` | `#FFFFFF` | Cards and sheets |
| `muted` | `#6B6B85` | Secondary text, inactive icons |
| `line` | `#ECE6DE` | Borders and dividers |
| `soft` | `#F7F3ED` | Inputs, quiet surfaces |

Supporting tints: `coralTint #FFF0ED`, `amberTint #FFF6E3`,
`mintTint #E8F7F1`, `indigoTint #EEEDF9`.

**Rules**

- Amber is a fill, never small text on white. Pair it with `ink`.
- Coral is an accent. Do not use it for body text on white.
- Mint text on `mintTint` is allowed at 11pt and above; for smaller text use
  `#0B6B4F`.
- A surface is either `cream` or `white`. There is no third background.

Dark mode mirrors the tokens with `#0F0F1E` as the background and `#1C1C32`
as the card surface. The brand colours stay the same.

## 4. Typography

| Role | Family | Weight | Size / line |
| --- | --- | --- | --- |
| Display | Sora | 800 | 30 / 36 |
| H1 | Sora | 800 | 24 / 30 |
| H2 | Sora | 700 | 20 / 26 |
| H3 | Sora | 700 | 17 / 22 |
| Title | Inter | 700 | 15 / 20 |
| Body | Inter | 400 | 14 / 20 |
| Body strong | Inter | 600 | 14 / 20 |
| Small | Inter | 400 | 12 / 16 |
| Label | Inter | 700 | 11 / 14 |
| Micro | Inter | 600 | 10 / 13 |

- Two families only: Sora for headings, Inter for everything else.
- Fonts are bundled in `frontend/assets/fonts/`, never fetched at runtime.
- Body text never goes below 12pt. Interactive labels never below 11pt.
- Numbers in a rating or a countdown use tabular figures.

## 5. Space and shape

- 4pt grid: 4, 8, 12, 16, 20, 24, 32, 40.
- Screen edge padding: 24 on phones, 32 on wide layouts.
- Card radius: 24. Button radius: 14. Pill: fully rounded. Sheet top: 28.
- Card shadow: `0 6 20 rgba(20,20,43,0.07)`. No 1px border unless the card is
  on a white sheet, where `line` is used.
- Minimum tap target: 48×48.
- Primary button height: 52. Secondary: 44.

## 6. Motion

- Navigation and state changes: 200ms, `easeOutCubic`.
- Celebration: 400ms spring. One confetti moment per completed session, never
  per tap.
- Haptics: light on send and accept, medium on check-in and finish.
- Respect `MediaQuery.disableAnimations`. When it is true, celebrations are
  skipped and transitions become cuts.
- No looping animation except the splash and auth Lotties.

## 7. Components

All live in `frontend/lib/core/widgets/`.

| Component | Purpose |
| --- | --- |
| `AppCard` | White surface, 24 radius, soft shadow, optional tap |
| `AppButton` | `primary` (indigo), `accent` (amber), `outline`, `ghost`; loading and disabled states |
| `AppPill` | Status and metadata: mint, amber, coral, indigo, neutral |
| `AppAvatar` | Gradient initials avatar; optional image; optional verified dot |
| `SectionHeader` | Section title plus one trailing action |
| `AppSkeleton` | Loading placeholder with a quiet shimmer |
| `EmptyView` | Empty state with icon, title, message, action |
| `FailureView` | Error state with a retry action and human copy |
| `LoadingView` | Loading state; cards/detail variants |

Feature-specific components stay in their feature:

| Component | Feature |
| --- | --- |
| `TutorCard` | `tutors` |
| `MatchCandidateTile` | `matching` |
| `SessionTimeline` | `sessions` |
| `CertificateRing` | `incentives` |
| `NotificationTile` | `notifications` |

## 8. Screen patterns

**Home**

1. Greeting and notification bell.
2. The composer: course chips plus a "View more" chip that opens the full
   catalogue as a list, one free-text field, one amber CTA.
3. The live session pass, if there is one.
4. A short tutor rail.
5. A tutor-only nudge.

**Find a tutor**

1. Course context in the app bar.
2. Search and filters.
3. One card per tutor: person first, evidence second, CTA last.
4. A request sheet, never a full page form.

**Session**

1. The pass: what, with whom, when.
2. The timeline: requested → accepted → starting → in session → rated.
3. Two actions only: *I'm here* and *Join*.
4. Safety note and session facts.

**Tutor HQ**

1. Progress ring to Verified.
2. Requests waiting, with Accept and *Not this one*.
3. This week's numbers.
4. Certificate progress.
5. Availability toggle.

## 9. Accessibility

- WCAG AA for body text; amber and coral are never used as small text on white.
- All icon-only buttons carry a `tooltip` and a semantic label.
- Loading and error changes are announced with `Semantics(liveRegion: true)`.
- Text scaling up to 200% must not clip a primary action.
- The app is usable with one hand: primary actions sit in the bottom third.

## 10. Implementation map

```
core/theme/app_colors.dart       Palette and semantic colour names
core/theme/app_palette.dart      ThemeExtension: the colours a widget may ask for
core/theme/app_typography.dart   TextTheme and display styles
core/theme/app_theme.dart        Material 3 theme for light and dark
core/constants/app_dimens.dart   Spacing, radii, component sizes, shadow
core/widgets/                    Shared components listed above
assets/fonts/                    Inter and Sora, variable, bundled
```

A screen does not hard-code a colour, radius, or font size. It reads the theme,
`AppColors`, `AppTypography`, or `AppDimens`.

### Fonts

Both families ship as variable fonts in `assets/fonts/`, declared once per
weight in `pubspec.yaml`. Styles set `fontWeight` **and** `fontVariations`: the
weight is the intent, and the variation is what tells the variable font to honour
it. `test/core/theme/bundled_fonts_test.dart` fails if a file is missing or an
axis no longer changes the rendered width.

### Design preview

In a debug build, open `/design-preview` to see the palette, the type scale, and
every component state on a real device. The route is registered only under
`kDebugMode`; a release build has no such screen.


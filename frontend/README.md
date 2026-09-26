# Ulearn — Flutter client

The mobile client for Ulearn, a peer-to-peer academic support network. See
[the architecture document](../docs/architecture.md) for system boundaries and
[the repository guide](../AGENTS.md) for contribution rules.

## Requirements

| Tool           | Version                       |
| -------------- | ----------------------------- |
| Flutter        | `>=3.47.0` (pinned in pubspec) |
| Dart           | `^3.13.1` (implied by Flutter)  |
| Android SDK    | 36.x                          |

Check with `flutter doctor`. The `flutter` constraint in `pubspec.yaml` means an
older SDK fails at `pub get` with a clear message rather than later on a missing
API.

## Targets

Android, iOS, and web. Desktop runners were removed: the pilot is mobile, and
each runner is a build surface that has to keep compiling. Web is retained as a
stakeholder demo target that needs no device.

## Running

```bash
flutter pub get
flutter run                                   # attached device or emulator
flutter run --dart-define=API_BASE_URL=https://api.example.org
```

### The API base URL

There is no hardcoded host. `AppConfig` reads `API_BASE_URL` from
`--dart-define`, falling back to `http://10.0.2.2:8000` for local development.

`10.0.2.2` is the Android emulator's alias for the host machine's loopback.
`localhost` inside the emulator is the emulator itself, which is the single most
common cause of a client that works on web and cannot reach a local API on
Android. For a physical device, pass your machine's LAN address explicitly.

Secrets are never compiled into the client. The API holds no secrets; the
access and refresh tokens are held in `flutter_secure_storage`.

## Validation

```bash
flutter analyze
flutter test
flutter test --coverage
```

`flutter analyze` is the gate CI enforces. It runs `very_good_analysis`, with
three rules relaxed in `analysis_options.yaml` and the reasoning recorded there.

## Layout

Feature-first, two layers per feature, because matching, validation, grade, and
rating rules are owned by the backend:

```text
lib/
├── main.dart          # ProviderScope and runApp only
├── app/               # MaterialApp.router, GoRouter, auth redirect guard
├── core/              # shared foundations, no feature knowledge
└── features/<name>/   # data/ and presentation/
```

`core/` must never import from `features/`. A feature must not import another
feature's `presentation/` layer; cross-feature reuse goes through the owning
feature's `data/repositories/` contract.

Tests mirror `lib/`. `test/integration/` is reserved for end-to-end runs of the
real app.

## Known deferrals

- **Application id.** `com.ulearn.app` is a placeholder pending a registered
  domain. It is free to change until a keystore is signed or a store listing is
  created; after that it is effectively permanent. Update
  `android/app/build.gradle.kts` (`namespace` and `applicationId`), the Kotlin
  `MainActivity` package, and the iOS `PRODUCT_BUNDLE_IDENTIFIER` together — a
  mismatch between namespace and applicationId fails the Android build.
- **Branding.** The web manifest still carries the Flutter template blue. It
  moves when the brand seed colour is set.
- **Launcher icon.** Still the default Flutter mark.

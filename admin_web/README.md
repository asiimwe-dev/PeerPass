# PeerPass Admin Web

The separate Flutter web console for MUST pilot operations.

## Local development

Start the backend first, then run:

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

The API URL is a build-time value. Production builds must provide the HTTPS
origin of the deployed PeerPass API:

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://api.example.invalid
```

Only provisioned accounts with the backend `admin` role can sign in. The
console does not provide public admin registration or role assignment.

## Pilot surface

- **Users** shows the bounded, privacy-safe operational user list.
- **Audit log** shows append-only records of privileged admin actions.

Loading, empty, server-error, and retry states are explicit. The console does
not display passwords, refresh tokens, consent timestamps, competency evidence,
or internal database identifiers.

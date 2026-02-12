# Plan — Patrol (Mobile) Coverage

> **Purpose**: Actionable plan for mobile E2E testing with Patrol — migration steps, file layout, and coverage matrix.

Architecture and key decisions: [pangea-automated-test-design.md](pangea-automated-test-design.md) § "Mobile architecture (Patrol)"
Web & accessibility plan: [web-and-accessibility-next-steps.md](web-and-accessibility-next-steps.md)

---

## Status: Not started

Patrol testing depends on web E2E infrastructure being stable first. The `trigger-map.json` and `select-tests.js` are already designed to support both platforms (`web` and `mobile` fields per entry).

---

## Migration steps

1. Install Patrol: `flutter pub add patrol --dev`, configure `pubspec.yaml` patrol section, native side setup (Android `AndroidManifest.xml`, iOS test runner)
2. Write `integration_test/patrol/common.dart` — shared login helper using `$('Login')` finders
3. Write `login_test.dart` to validate wiring end-to-end
4. Incrementally migrate existing `app_test.dart` flows to Patrol format
5. Add native-only tests (permissions, push notifications, backgrounding)
6. Add mobile CI workflow — start with Android emulator in GitHub Actions, graduate to Firebase Test Lab

---

## File layout

```
integration_test/
  app_test.dart              # Existing FluffyChat integration tests
  patrol/
    common.dart              # Shared login helper
    login_test.dart          # Basic login validation
    send_message_test.dart
    permissions_test.dart    # Native permission dialogs
    ...
```

---

## Coverage matrix

| Flow                    | Status | Notes                   |
| ----------------------- | :----: | ----------------------- |
| Login                   |   ⬜   |                         |
| Chat list navigation    |   ⬜   |                         |
| Open chat               |   ⬜   |                         |
| Send message            |   ⬜   |                         |
| Message toolbar         |   ⬜   |                         |
| Course discovery        |   ⬜   |                         |
| Settings                |   ⬜   |                         |
| Analytics               |   ⬜   |                         |
| Create DM               |   ⬜   |                         |
| Logout                  |   ⬜   |                         |
| Permission dialogs      |   ⬜   | Native OS — Patrol-only |
| Push notifications      |   ⬜   | Native OS — Patrol-only |
| Background / foreground |   ⬜   | Native OS — Patrol-only |

# E2E Test Plan — Web (Playwright) & Mobile (Patrol)

## Goal

End-to-end coverage across all platforms the app ships on.

| Platform      | Tool                        | Runs against                                 |
| ------------- | --------------------------- | -------------------------------------------- |
| **Web**       | Playwright Test             | Live staging deploy (`app.staging.pangea.chat`) |
| **Android / iOS** | Patrol + `integration_test` | Emulators / real devices / Firebase Test Lab |

Tests are diff-triggered: when a release touches files matching a script's globs, that script runs. Login always runs as a smoke test.

---

## Status

| Phase | Description | Status |
| ----- | ----------- | ------ |
| 1. Semantics | Add tooltips / `Semantics` labels so Playwright can find elements | P0 ✅, P1/P2 remaining |
| 2. Infrastructure | Playwright config, fixtures, auth setup, trigger map, test selector | ✅ |
| 3. CI/CD | GitHub Actions workflow, Copilot setup steps, e2e-tester agent | ✅ |
| 4. More web specs | Write remaining `*.spec.ts` for each flow | ⬜ |
| 5. Mobile (Patrol) | Install Patrol, write mobile tests, mobile CI | ⬜ |

### Implemented files

```
e2e/
  fixtures.ts              # Enables Flutter semantics tree on each page load
  auth.setup.ts            # Login once, save auth state
  playwright.config.ts     # Chromium-only, auth setup project
  trigger-map.json         # Script → glob mapping (11 entries)
  select-tests.js          # Diff-based test selector (uses minimatch)
  scripts/
    login.spec.ts          # Login flow — landing page → email → credentials → chat list
  .auth/                   # gitignored — saved login state

.github/
  workflows/
    e2e-tests.yml          # Post-deploy, manual, nightly triggers
    copilot-setup-steps.yml # Node + Playwright for Copilot coding agent
  agents/
    e2e-tester.md          # Cloud agent profile with Flutter-Playwright patterns
  instructions/
    e2e-testing.instructions.md # Conventions and patterns for editing e2e files
```

---

## Semantics work remaining (Phase 1 P1/P2)

### P1 — Blocks specific feature flows

| Area              | What to fix                                              | Files                                    |
| ----------------- | -------------------------------------------------------- | ---------------------------------------- |
| Message toolbar   | Word card, practice, translation buttons need tooltips   | `lib/pangea/toolbar/widgets/`            |
| Choreographer     | IGC accept/reject buttons, IT option buttons need labels | `lib/pangea/choreographer/widgets/`      |
| Course discovery  | Course tiles need semantic labels with course name       | `lib/pangea/course_creation/widgets/`    |
| Settings          | Unlabeled `IconButton`s across settings sub-pages        | `lib/pages/settings/`                    |
| Activity sessions | Start, skip, submit buttons need tooltips                | `lib/pangea/activity_sessions/`          |
| Analytics         | Construct tiles, practice buttons                        | `lib/pangea/analytics_page/`, `lib/pangea/analytics_practice/` |

### P2 — Nice-to-have for richer assertions

- Add `semanticLabel` to `Image.asset()`, `SvgPicture`
- Add `excludeFromSemantics: true` to purely decorative icons
- Ensure `AlertDialog` titles appear in semantics tree

---

## Test flows & coverage

Each flow maps to a web spec and/or mobile Patrol test via `e2e/trigger-map.json`.

| Flow                         | Web | Mobile | Notes |
| ---------------------------- | :-: | :----: | ----- |
| Login                        | ✅  |   ⬜   | |
| Chat list navigation         | ⬜  |   ⬜   | |
| Open chat                    | ⬜  |   ⬜   | |
| Send message                 | ⬜  |   ⬜   | |
| Message toolbar (TTS, etc.)  | ⬜  |   ⬜   | Needs P1 semantics |
| Course discovery             | ⬜  |   ⬜   | Needs P1 semantics |
| Settings                     | ⬜  |   ⬜   | Needs P1 semantics |
| Analytics                    | ⬜  |   ⬜   | Needs P1 semantics |
| Create DM                    | ⬜  |   ⬜   | |
| Logout                       | ⬜  |   ⬜   | |
| Permission dialogs           | ❌  |   ⬜   | Mobile-only (native) |
| Push notifications           | ❌  |   ⬜   | Mobile-only (native) |
| Background / foreground      | ❌  |   ⬜   | Mobile-only (native) |

---

## CI modes

Defined in `.github/workflows/e2e-tests.yml`.

| Mode     | Trigger                           | What runs                                |
| -------- | --------------------------------- | ---------------------------------------- |
| **Smoke**  | Manual                          | `login` only                             |
| **Diff**   | After `Main Deploy Workflow`    | Scripts matching changed files + `login` |
| **Full**   | Nightly (6am UTC) / manual      | All scripts                              |

### Secrets required

| Secret                  | Description                       |
| ----------------------- | --------------------------------- |
| `STAGING_TEST_USER`     | Test account email                |
| `STAGING_TEST_PASSWORD` | Test account password             |

---

## Execution model

```
┌─────────────────────────────────┐
│  Option D: Cloud Copilot Agent  │  Self-healing — agent diagnoses
│  .github/agents/e2e-tester.md   │  and fixes broken locators
└───────────┬─────────────────────┘
            │ creates / updates specs
┌───────────▼─────────────────────┐
│  Option C: Hybrid Authoring     │  Agent or developer writes specs
│  Playwright MCP → *.spec.ts     │  interactively, commits them
└───────────┬─────────────────────┘
            │ committed specs run in
┌───────────▼─────────────────────┐
│  Option B: Deterministic CI     │  npx playwright test
│  e2e-tests.yml                  │  Fast, free, every deploy  ← foundation
└─────────────────────────────────┘
```

---

## Mobile testing (Patrol) — future

Patrol extends `integration_test` with native automation (permissions, system dialogs, backgrounding). Not yet installed.

**Key decisions:**
- Finders: text-based (`$('Login')`) and type-based (`find.byType(ChatView)`) — no `ValueKey`s
- App launch: call `app.main()` directly (same as existing `app_test.dart`)
- Backend: `--dart-define=SYNAPSE_URL=...` for staging or local homeserver
- CI: start with Android emulator in GitHub Actions, graduate to Firebase Test Lab

**Migration path:**
1. `flutter pub add patrol --dev`, configure `pubspec.yaml` patrol section, native side setup
2. Write `integration_test/patrol/common.dart` (shared login helper)
3. Write `login_test.dart` to validate wiring
4. Incrementally migrate existing `app_test.dart` flows
5. Add native-only tests (permissions, push notifications)
6. Add mobile CI workflow

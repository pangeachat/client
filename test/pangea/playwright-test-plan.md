# E2E Test Plan — Web (Playwright) & Mobile (Patrol)

## Goals

Four capabilities, layered on top of each other:

### 1. Nightly smoke tests

**What**: Cron job runs login + core flow specs against staging every night.
**How**: `.github/workflows/e2e-tests.yml` — nightly trigger (6am UTC), runs all specs in `e2e/scripts/`.
**Status**: ✅ Workflow exists. Login spec passes. More specs needed.

### 2. Diff-triggered tests on release

**What**: When a release deploys to staging, only run specs whose source files were touched.
**How**: `e2e-tests.yml` post-deploy trigger chains off "Main Deploy Workflow". `select-tests.js` reads the diff, matches against `trigger-map.json` globs, runs only affected specs (login always included).
**Status**: ✅ Wired up. Coverage is thin — most flows don't have specs yet.

### 3. Guided local test authoring (skill)

**What**: A developer says "write a Playwright test for the settings flow" and Copilot walks them through it — semantics audit, label fixes, spec writing, trigger-map wiring.
**How**: `.github/skills/write-e2e-test/SKILL.md` provides the step-by-step procedure. `.github/instructions/e2e-testing.instructions.md` provides conventions (loaded automatically when editing `e2e/` files).
**Status**: ✅ Skill and instructions exist.

### 4. Cloud agent self-healing

**What**: Copilot coding agent picks up failing-test issues, diagnoses broken locators, fixes Dart semantics labels and spec files, opens a PR.
**How**: `.github/agents/e2e-tester.md` agent profile. `.github/workflows/copilot-setup-steps.yml` installs Node + Playwright in the agent's environment.
**Status**: ✅ Agent profile and setup steps exist. Untested — needs a real failure to exercise.

---

## Build status

| Phase              | Description                                                       | Status                                 |
| ------------------ | ----------------------------------------------------------------- | -------------------------------------- |
| 1. Semantics       | Tooltips and `Semantics` wrappers so Playwright can find elements | Login flow done, most of app remaining |
| 2. Infrastructure  | Config, fixtures, auth, trigger map, test selector                | ✅                                     |
| 3. CI/CD           | Workflow, Copilot setup steps, agent profile, skill               | ✅                                     |
| 4. More web specs  | Remaining `*.spec.ts` for each flow                               | ⬜                                     |
| 5. Mobile (Patrol) | Patrol tests and mobile CI                                        | ⬜                                     |

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
  skills/
    write-e2e-test/SKILL.md # Guided procedure for writing new specs
```

---

## Semantics work remaining

Flutter renders to `<canvas>`, so Playwright can't see buttons, text fields, etc. the way it can with normal HTML. Instead, it reads Flutter's **semantics tree** — an accessibility layer that maps widgets to ARIA roles (like `button "Login"` or `textbox "Password"`). If a widget doesn't have a tooltip, text child, or `Semantics` wrapper, Playwright sees it as an unnamed `generic` node and can't interact with it.

Only the login flow has full semantics coverage so far. Before writing a spec for a new flow, walk through it and fix any unlabeled elements:

1. Run the app in Chrome, use Playwright MCP's `browser_snapshot` (or DevTools → Accessibility tab) to see what Playwright sees
2. Find elements that show as unnamed `generic` or unlabeled `button`
3. Fix them:
   - `IconButton` → add `tooltip:` parameter
   - `GestureDetector` / `InkWell` → wrap in `Semantics(label: '...', button: true, child: ...)`
   - Decorative images → add `excludeFromSemantics: true`
4. Files outside `lib/pangea/` need `// #Pangea` / `// Pangea#` markers around changes
5. Use existing L10n keys where possible — check `intl_en.arb`

---

## Test flows & coverage

Each flow maps to a web spec and/or mobile Patrol test via `e2e/trigger-map.json`.

| Flow                        | Web | Mobile | Notes                |
| --------------------------- | :-: | :----: | -------------------- |
| Login                       | ✅  |   ⬜   |                      |
| Chat list navigation        | ⬜  |   ⬜   |                      |
| Open chat                   | ⬜  |   ⬜   |                      |
| Send message                | ⬜  |   ⬜   |                      |
| Message toolbar (TTS, etc.) | ⬜  |   ⬜   | Needs P1 semantics   |
| Course discovery            | ⬜  |   ⬜   | Needs P1 semantics   |
| Settings                    | ⬜  |   ⬜   | Needs P1 semantics   |
| Analytics                   | ⬜  |   ⬜   | Needs P1 semantics   |
| Create DM                   | ⬜  |   ⬜   |                      |
| Logout                      | ⬜  |   ⬜   |                      |
| Permission dialogs          | ❌  |   ⬜   | Mobile-only (native) |
| Push notifications          | ❌  |   ⬜   | Mobile-only (native) |
| Background / foreground     | ❌  |   ⬜   | Mobile-only (native) |

---

## CI modes

Defined in `.github/workflows/e2e-tests.yml`.

| Mode      | Trigger                      | What runs                                |
| --------- | ---------------------------- | ---------------------------------------- |
| **Smoke** | Manual                       | `login` only                             |
| **Diff**  | After `Main Deploy Workflow` | Scripts matching changed files + `login` |
| **Full**  | Nightly (6am UTC) / manual   | All scripts                              |

### Secrets required (manual setup — repo Settings → Secrets → Actions)

| Secret                  | Description           | Set? |
| ----------------------- | --------------------- | ---- |
| `STAGING_TEST_USER`     | Test account email    | ⬜   |
| `STAGING_TEST_PASSWORD` | Test account password | ⬜   |

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

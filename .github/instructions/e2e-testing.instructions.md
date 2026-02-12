---
applyTo: "client/e2e/**,client/integration_test/**,client/test/pangea/playwright-test-plan.md,client/.github/workflows/e2e-*.yml,client/.github/workflows/copilot-setup-steps.yml,client/.github/agents/**,client/.github/skills/write-e2e-test/**"
---

# E2E Testing — Web (Playwright) & Mobile (Patrol)

Master plan: `client/test/pangea/playwright-test-plan.md`

## Architecture

| Platform      | Tool                                        | Target                                        |
| ------------- | ------------------------------------------- | --------------------------------------------- |
| Web           | Playwright (MCP for authoring, Test for CI) | Live staging deploy — no build step           |
| Android / iOS | Patrol + `integration_test`                 | Emulators, real devices, or Firebase Test Lab |

## Key decisions (locked in)

1. **`trigger-map.json` format**: `{ "script": { "globs": [...], "web": "path|null", "mobile": "path|null" } }`. Single source of truth for diff-triggered test selection. Lives at `client/e2e/trigger-map.json`.

2. **Patrol finders**: Use **text-based** (`$('Login to my account')`) and **type-based** (`find.byType(ChatView)`) finders — matching existing integration test style. Do NOT add `ValueKey`s to widgets for test purposes. The codebase has ~7 static Keys and zero `Semantics` labels; text/type finders require no widget modifications.

3. **Patrol app launch**: Call `app.main()` directly (same as existing `app_test.dart`). Patrol's binding replaces `IntegrationTestWidgetsFlutterBinding` before `main()` runs, so `ensureInitialized()` inside `main()` is a no-op. Do NOT refactor `main.dart` to extract `buildApp()`.

4. **Backend target (parameterizable)**: Patrol tests target staging or local homeserver via `--dart-define=SYNAPSE_URL=...`. The app reads this through `Environment.synapseURL`. No code change needed.

5. **Credential delivery**:
   - Playwright (web): shell env vars `$TEST_USER`, `$TEST_PASSWORD`
   - Patrol (mobile): Dart compile-time defines `--dart-define=TEST_USER=...`
   - CI: both sourced from GitHub Actions secrets `STAGING_TEST_USER`, `STAGING_TEST_PASSWORD`

6. **Layered execution model**: Option B (deterministic CI) is the foundation. Option C (agent authors specs) for writing new tests. Option D (cloud Copilot agent) for self-healing. Option A (local MCP) for developer exploration.

## File layout

```
client/
  e2e/                              # Playwright (web)
    fixtures.ts
    auth.setup.ts
    playwright.config.ts
    trigger-map.json                 # canonical — web + mobile
    select-tests.js                  # --platform web|mobile|all
    scripts/*.spec.ts
  integration_test/                  # Patrol (mobile)
    app_test.dart                    # existing FluffyChat tests
    patrol/                          # new Patrol tests
      common.dart
      login_test.dart
      send_message_test.dart
      permissions_test.dart
      ...
```

## Phase 1 prerequisite

Playwright (web) requires Flutter semantics tree. Before writing web specs, add `tooltip` to all `IconButton`s and `Semantics` wrappers to `GestureDetector`/`InkWell` widgets. See Phase 1 tables in the plan for the full list. Patrol (mobile) does NOT need these — it uses Flutter's widget tree directly.

## Conventions

- Playwright identifies elements by ARIA role + name (from tooltips / Semantics labels / Text children)
- Patrol identifies elements by text content, widget type, or icon — never by Key
- All new `IconButton`s must have `tooltip:` (for Playwright + accessibility)
- All new tappable `GestureDetector`/`InkWell` should be wrapped in `Semantics(label:..., button: true)`
- Decorative images: `excludeFromSemantics: true`
- Meaningful images: `semanticLabel: '...'`

## Flutter-Playwright Patterns (critical)

These patterns are required because Flutter renders to `<canvas>` and its semantics tree behaves differently from standard HTML.

1. **Semantics enablement**: Flutter positions `flt-semantics-placeholder` **off-screen**. Use `dispatchEvent("click")` — regular `.click()` and `force: true` both fail. The shared fixture in `e2e/fixtures.ts` handles this automatically.

2. **Text input filling**: Canvas-based inputs need explicit `.click()` to focus before `.fill()`, with `waitForTimeout(500)` between fields. Without this, the first field's value gets lost when focus moves.

3. **Login timeout**: Matrix server round-trip takes up to 30s. Always use `{ timeout: 30000 }` on `toHaveURL(/\/rooms/)` after login.

4. **Responsive layout**: At headless Chromium's default viewport, the app renders a nav rail (Home, All chats, Settings) — NOT a header with a Search button. Assert against what the viewport actually shows.

5. **Test file imports**: All spec files import `{ test, expect }` from `../fixtures`, NOT from `@playwright/test`. The fixture handles navigation to `/` and semantics enablement — tests must NOT repeat this.

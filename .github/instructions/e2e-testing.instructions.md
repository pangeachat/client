---
applyTo: "client/e2e/**,client/integration_test/**,client/.github/workflows/e2e-*.yml,client/.github/workflows/copilot-setup-steps.yml,client/.github/agents/**,client/.github/skills/write-e2e-test/**"
---

# E2E Testing — Web (Playwright) & Mobile (Patrol)

> **Purpose**: Conventions and patterns auto-loaded by Copilot when editing `e2e/` files. The single source of truth for _how_ to write correct test code.

- Design doc: `client/e2e/pangea-automated-test-design.md`
- Actionable plan: `client/e2e/web-and-accessibility-next-steps.md`
- Skilled procedure: `.github/skills/write-e2e-test/SKILL.md`

## Architecture

| Platform      | Tool                                        | Target                                        |
| ------------- | ------------------------------------------- | --------------------------------------------- |
| Web           | Playwright (MCP for authoring, Test for CI) | Live staging deploy — no build step           |
| Android / iOS | Patrol + `integration_test`                 | Emulators, real devices, or Firebase Test Lab |

## Key decisions (locked in)

1. **`trigger-map.json` format**: `{ "script": { "globs": [...], "web": "path|null", "mobile": "path|null" } }`. Single source of truth for diff-triggered test selection. Lives at `client/e2e/trigger-map.json`.

2. **Patrol finders**: Use **text-based** (`$('Login to my account')`) and **type-based** (`find.byType(ChatView)`) finders — matching existing integration test style. Do NOT add `ValueKey`s to widgets for test purposes.

3. **Patrol app launch**: Call `app.main()` directly (same as existing `app_test.dart`). Patrol's binding replaces `IntegrationTestWidgetsFlutterBinding` before `main()` runs, so `ensureInitialized()` inside `main()` is a no-op. Do NOT refactor `main.dart` to extract `buildApp()`.

4. **Backend target (parameterizable)**: Patrol tests target staging or local homeserver via `--dart-define=SYNAPSE_URL=...`. The app reads this through `Environment.synapseURL`. No code change needed.

5. **Credential delivery**:
   - Playwright (web): shell env vars `$TEST_USER`, `$TEST_PASSWORD`
   - Patrol (mobile): Dart compile-time defines `--dart-define=TEST_USER=...`
   - CI: both sourced from GitHub Actions secrets `STAGING_TEST_USER`, `STAGING_TEST_PASSWORD`

6. **Layered execution model**: Deterministic CI is the foundation. The `add-e2e-coverage` skill guides spec authoring. The `e2e-tester` cloud agent handles self-healing. Playwright MCP enables local developer exploration.

## File layout

```
client/
  e2e/                              # Playwright (web)
    fixtures.ts
    auth.setup.ts
    playwright.config.ts
    trigger-map.json                 # canonical — web + mobile
    select-tests.js                  # --platform web|mobile|all
    scripts/
      login.spec.ts                 # Login flow spec
      a11y.spec.ts                  # Accessibility audits (axe-core, WCAG 2.1 AA)
  integration_test/                  # Patrol (mobile)
    app_test.dart                    # existing FluffyChat tests
    patrol/                          # new Patrol tests
      common.dart
      login_test.dart
      send_message_test.dart
      permissions_test.dart
      ...
```

## Semantics prerequisite

Playwright (web) requires Flutter semantics tree. Before writing a web spec for a new flow, audit and fix unlabeled widgets using the `add-e2e-coverage` skill (Steps 2–3). Patrol (mobile) does NOT need these — it uses Flutter's widget tree directly.

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

6. **Auth state with IndexedDB**: `auth.setup.ts` saves state with `storageState({ path, indexedDB: true })`. Flutter's Matrix client stores session tokens in IndexedDB, not cookies/localStorage. Without `indexedDB: true`, authenticated tests can't restore the session.

## Accessibility testing (axe-core)

`e2e/scripts/a11y.spec.ts` runs WCAG 2.1 AA audits using `@axe-core/playwright`. When adding a new flow spec, also add an axe-core audit for that flow's pages.

- Audits are scoped to `flt-semantics-host` (Flutter's semantics overlay) — the canvas is opaque to axe
- Tags: `wcag2a`, `wcag2aa`, `wcag21aa`
- The shared `auditPage(page)` helper handles the AxeBuilder setup — just navigate to the page and call it
- Unauthenticated tests use `test.use({ storageState: { cookies: [], origins: [] } })`
- Authenticated tests inherit the saved auth state (including IndexedDB)
- Zero-tolerance: tests assert `violations.toHaveLength(0)` — fix the widget, don't allowlist violations

### What axe can't check (Flutter canvas limitation)

- Color contrast — axe can't inspect pixels inside `<canvas>`
- Visual layout — the rendered UI is canvas, not DOM

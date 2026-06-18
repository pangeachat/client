---
applyTo: "**/*test*,**/test/**,**/integration_test/**"
---

# Testing Guide (Client)

Follows the [cross-repo testing strategy](../../../.github/instructions/testing.instructions.md) — see that doc for tier definitions (unit / integration / e2e), conventions, and rationale. This doc covers client-specific details only.

## Stack

- **Framework**: `flutter test` (Dart test runner), Playwright Test (web E2E + axe-core a11y)
- **Language**: Dart, TypeScript (Playwright specs)
- **Unit/widget tests**: `test/` directory
- **Integration tests**: `integration_test/` (Flutter, not in CI), `e2e/scripts/` (Playwright, CI via `e2e-tests.yml`)

## File layout

```
test/
  *.dart                        # Upstream fluffychat tests — DO NOT MOVE (merge conflicts)
  utils/                        # Upstream test helpers — DO NOT MOVE
  pangea/                       # All Pangea unit/widget tests — safe to reorganize
    onboarding_tests/           # Example: feature-grouped subdir
    choreo_endpoint_test.dart   # Confirm client and choreo endpoint compatibility
integration_test/
  app_test.dart                 # Flutter integration (Matrix auth flows) — not in CI
e2e/
  scripts/                      # Browser Playwright specs (UI flows)
    login-logout.spec.ts
    a11y.spec.ts
    settings.spec.ts
    analytics.spec.ts
    course-chat-navigation.spec.ts
  auth.setup.ts                 # Login and save state for testing usage
  fixtures.ts                   # Shared browser fixture
  playwright.config.ts
  trigger-map.json              # CI: maps file globs → which specs to run
```

**Adding new browser specs** (`e2e/scripts/`): subdirectories are fine, Playwright recurses. Update `trigger-map.json`.

**Adding new Pangea unit tests**: `test/pangea/`. Feature subdirectories are fine — `flutter test` recurses. Don't add files to `test/` root (upstream owns that layer).

## Where choreo/CMS tests live

The PR runner (`flutter test` via `integrate.yaml`) is a plain ubuntu-latest with no choreo credentials and no running server. Nothing in `test/` can make a real network call. Three tiers cover the space:

| Goal | Location | CI gate | Mock mechanism |
|---|---|---|---|
| Client-side logic: request serialization, response parsing, error handling | `test/pangea/` | Every PR | `http.MockClient` in Dart intercepts `Requests.post`/`.get`, returns a canned JSON fixture. No network. |
| End-to-end UI flows that trigger choreo | `e2e/scripts/` | Post-deploy + nightly | Choreo requests are intercepted by Playwright specs and `mock: true` is inserted. |

### Endpoint tests — `test/pangea/choreo_endpoint_test.dart`

Unit tests in `choreo_endpoint_test.dart` directly send mock requests to the staging choreographer. Endpoint unit tests confirm compatibility between the sent mock requests and `2-step-choreographer`, and between received responses and their corresponding client `Response` classes.

Every choreographer endpoint accessed by client has an individual unit test. Emulate the structure of existing tests, with endpoint-specific values substituted in as needed. Add optional `mock` members to relevant Request classes, so sent requests always have `mock: true`.

Env vars required (add to `client/.env` or export before running): 
- `TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD` — staging test account (same as browser specs)

## Current State

- **Unit tests**: Dart tests in `test/` and `test/pangea/` — model parsing, schema validation, data transforms, choreographer endpoint tests.
- **Integration tests**:
  - **Playwright browser** (`e2e/scripts/`): Login flow + axe-core WCAG 2.1 AA. Runs post-deploy, nightly, and on manual dispatch. See [playwright-testing.instructions.md](playwright-testing.instructions.md) and [`e2e/README.md`](../../e2e/README.md).
  - **Flutter** (`integration_test/app_test.dart`): Matrix login/logout/nav only, not in CI, no choreo coverage.
- **E2E tests**: Playwright tests in `e2e/` navigate the app along defined flows, using mocked values for paid third-party calls.

## CI

- `flutter test` runs on every PR via `integrate.yaml` — discovers all tests in `test/`
- `e2e-tests.yml` runs Playwright specs against staging in three modes:
  - **smoke**: login spec only (manual)
  - **diff**: post-deploy, browser specs selected by `trigger-map.json`
  - **full**: nightly 6am UTC + manual — all browser specs
  - Failures on post-deploy runs comment on the triggering PR

## Mock mode — bypassing paid choreo/CMS calls

When Playwright is run, all choreo requests are intercepted, and `mock: true` is injected. This tells the choreographer to run the full handler path but swap every paid third-party call for a canned response. No individual request class needs to be modified.

**Scope**: CMS reads use `Requests.get` and do not send `mock`; CMS doesn't have paid third-party calls so this is fine. If a choreo route returns 500 under `mock=true`, the handler likely lacks a registered mock producer — see the [playwright-testing instructions § Bypassing paid backend calls](playwright-testing.instructions.md#bypassing-paid-backend-calls---mocktrue) for how to file and fix.

## Commands

```bash
# Unit/widget tests (Dart)
flutter test                           # Run all
flutter test test/pangea/              # Run only Pangea tests
flutter test --name "test description" # Run a specific test by name

# Playwright browser specs (UI flows)
npm install && npx playwright install chromium           # One-time setup
npx playwright test --config e2e/playwright.config.ts --project=setup --project=chromium
npx playwright test e2e/scripts/login-logout.spec.ts --config e2e/playwright.config.ts  # Single spec
BASE_URL=https://app.staging.pangea.chat npx playwright test --config e2e/playwright.config.ts --project=setup --project=chromium
```

## Manual Testing

- **Device testing**: `flutter run` on physical device or emulator for full app flows
- **Playwright MCP**: Interactive browser exploration of the Flutter web build via Playwright MCP tools. Uses accessibility snapshots (`browser_snapshot`) to interact with Flutter's CanvasKit-rendered UI. Useful for authoring new specs and debugging semantics gaps. See [playwright-testing.instructions.md](playwright-testing.instructions.md) for the MCP interaction guide (login flow, navigation, accessibility enabling, tips)

## Future Work

- **Flutter integration CI** — `integration_test/app_test.dart` is not in CI; needs a device/emulator runner. Low priority given Playwright covers the same flows.

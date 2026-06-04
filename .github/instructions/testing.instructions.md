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
integration_test/
  app_test.dart                 # Flutter integration (Matrix auth flows) — not in CI
e2e/
  scripts/                      # Browser Playwright specs (UI flows)
    login.spec.ts
    logout.spec.ts
    a11y.spec.ts
    settings.spec.ts
    analytics.spec.ts
    course-chat-navigation.spec.ts
  api/                          # Playwright API specs (direct choreo calls, no browser)
    api-auth.setup.ts           # Matrix login via HTTP API → .auth/api-token.json
    helpers.ts                  # Shared headers builder (auth token + API key)
    specs/                      # One spec file per endpoint or endpoint group
      tokenize.spec.ts
      translation.spec.ts
      ...
  fixtures.ts                   # Shared browser fixture
  playwright.config.ts
  trigger-map.json              # CI: maps file globs → which specs to run
```

**Adding new browser specs** (`e2e/scripts/`): subdirectories are fine, Playwright recurses. Update `trigger-map.json`.

**Adding new API specs** (`e2e/api/specs/`): one file per endpoint or closely related group. No browser setup needed — just `request` fixture + shared headers from `helpers.ts`. No `trigger-map.json` entry needed; API specs always run in `full` and `diff` modes.

**Adding new Pangea unit tests**: `test/pangea/`. Feature subdirectories are fine — `flutter test` recurses. Don't add files to `test/` root (upstream owns that layer).

## Where choreo/CMS tests live

The PR runner (`flutter test` via `integrate.yaml`) is a plain ubuntu-latest with no choreo credentials and no running server. Nothing in `test/` can make a real network call. Three tiers cover the space:

| Goal | Location | CI gate | Mock mechanism |
|---|---|---|---|
| Client-side logic: request serialization, response parsing, error handling | `test/pangea/` | Every PR | `http.MockClient` in Dart intercepts `Requests.post`/`.get`, returns a canned JSON fixture. No network. |
| Choreo contract: each endpoint accepts valid requests and returns the expected shape | `e2e/api/specs/` | Post-deploy + nightly | Playwright `request` context calls real staging choreo directly with `mock: true` in the body. No browser. |
| End-to-end UI flows that trigger choreo | `e2e/scripts/` | Post-deploy + nightly | Choreo requests are intercepted by Playwright specs and `mock: true` is inserted. |

### Integration test — mock request fixtures

Each choreo endpoint should have a corresponding `mock_<endpoint>_request.json` file in its parent folder (i.e., client/lib/pangea/activity_feedback). This file exports valid request data (with realistic but static field values) that tests can import directly instead of re-constructing the request inline.

**Naming**: `mock_<endpoint>_request.json` — e.g. `mock_tokenize_request.json`, `mock_translation_request.json`.

**Contents**: json data, with every required field set to a realistic static value.

### Playwright API tests — `e2e/api/`

The `e2e/api/` tier calls staging choreo endpoints directly via Playwright's `request` context — no Flutter app, no browser. Auth is a one-time Matrix login via the Matrix client-server API (`/_matrix/client/v3/login`), performed in `api-auth.setup.ts` and cached to `.auth/api-token.json`. Every spec imports shared headers from `helpers.ts` (Matrix bearer token + choreo API key) and data from `mock_<endpoint>_request.json`.

Each spec in `e2e/api/specs/` covers one endpoint or a closely related group. Tests assert on HTTP status and the top-level shape of the response (required fields present, correct types) — not on content, which is canned mock data.

Env vars required (add to `client/.env` or export before running):
- `SYNAPSE_URL` — Matrix homeserver base URL (e.g. `https://matrix.staging.pangea.chat`)
- `CHOREO_API` — Choreo base URL (e.g. `https://pangea-chat.choreo.dev`)
- `TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD` — staging test account (same as browser specs)

## Current State

- **Unit tests**: Dart tests in `test/` and `test/pangea/` — model parsing, schema validation, data transforms. No choreo coverage yet.
- **Integration tests**:
  - **Playwright browser** (`e2e/scripts/`): Login flow + axe-core WCAG 2.1 AA. Runs post-deploy, nightly, and on manual dispatch. See [playwright-testing.instructions.md](playwright-testing.instructions.md) and [`e2e/README.md`](../../e2e/README.md).
  - **Playwright API** (`e2e/api/`): ⚠️ Not yet implemented — infrastructure and first specs pending.
  - **Flutter** (`integration_test/app_test.dart`): Matrix login/logout/nav only, not in CI, no choreo coverage.
- **E2E tests**: None. No tests currently call third-party paid APIs.

## CI

- `flutter test` runs on every PR via `integrate.yaml` — discovers all tests in `test/`
- `e2e-tests.yml` runs Playwright specs against staging in three modes:
  - **smoke**: login spec only (manual)
  - **diff**: post-deploy, browser specs selected by `trigger-map.json` + all API specs
  - **full**: nightly 6am UTC + manual — all browser specs + all API specs
  - Failures on post-deploy runs comment on the triggering PR

## Mock mode — bypassing paid choreo/CMS calls

All choreo POST requests flow through `Requests.post` → `BaseRequestModel.injectUserContext`. The mock seam lives there: when `PANGEA_MOCK_MODE=true` is set as a Dart compile-time define, `injectUserContext` appends `"mock": true` to every request body, which tells the choreographer to run the full handler path but swap every paid third-party call for a canned response. No individual request class needs to be modified.

**How to enable:**
```bash
# Flutter web — local Playwright target
flutter run -d chrome --web-port 8080 --dart-define=PANGEA_MOCK_MODE=true

# Flutter web — CI build for Playwright
flutter build web --dart-define=PANGEA_MOCK_MODE=true
```

**In code** (`base_request_model.dart`):
```dart
static const bool _mockMode = bool.fromEnvironment('PANGEA_MOCK_MODE');

static Map<String, dynamic> injectUserContext(...) {
  ...
  if (_mockMode) result['mock'] = true;
  ...
}
```

This flag is compile-time only — it's never set in production or development builds, only in test targets.

**Scope**: covers all handlers that go through `Requests.post`. CMS reads use `Requests.get` and do not send `mock`; CMS doesn't have paid third-party calls so this is fine. If a choreo route returns 500 under `mock=true`, the handler likely lacks a registered mock producer — see the [playwright-testing instructions § Bypassing paid backend calls](playwright-testing.instructions.md#bypassing-paid-backend-calls---mocktrue) for how to file and fix.

## Commands

```bash
# Unit/widget tests (Dart)
flutter test                           # Run all
flutter test test/pangea/              # Run only Pangea tests
flutter test --name "test description" # Run a specific test by name

# Playwright browser specs (UI flows)
npm install && npx playwright install chromium           # One-time setup
npx playwright test --config e2e/playwright.config.ts --project=setup --project=chromium
npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts  # Single spec
BASE_URL=https://app.staging.pangea.chat npx playwright test --config e2e/playwright.config.ts --project=setup --project=chromium

# Playwright API specs (direct choreo calls — no browser, no Flutter needed)
# Requires SYNAPSE_URL, CHOREO_API, TEST_MATRIX_USERNAME, TEST_MATRIX_PASSWORD in .env
npx playwright test --config e2e/playwright.config.ts --project=api-setup --project=api
npx playwright test e2e/api/specs/tokenize.spec.ts --config e2e/playwright.config.ts --project=api-setup --project=api

# Playwright browser specs with mock mode (no LLM costs)
flutter run -d chrome --web-port 8080 --dart-define=PANGEA_MOCK_MODE=true
# then in another terminal:
npx playwright test --config e2e/playwright.config.ts --project=setup --project=chromium
```

## Manual Testing

- **Device testing**: `flutter run` on physical device or emulator for full app flows
- **Playwright MCP**: Interactive browser exploration of the Flutter web build via Playwright MCP tools. Uses accessibility snapshots (`browser_snapshot`) to interact with Flutter's CanvasKit-rendered UI. Useful for authoring new specs and debugging semantics gaps. See [playwright-testing.instructions.md](playwright-testing.instructions.md) for the MCP interaction guide (login flow, navigation, accessibility enabling, tips)

## Future Work

- **Wire `PANGEA_MOCK_MODE` into `base_request_model.dart`** — the conditional `mock` flag described above needs to be implemented; right now the mock field is not set in any committed code.
- **Pass `--dart-define=PANGEA_MOCK_MODE=true` in `e2e-tests.yml`** — once the Dart flag is in place, add it to the `flutter build web` step in the CI workflow so all Playwright browser runs are cost-free by default.
- **Implement `e2e/api/` infrastructure** — `playwright.config.ts` api projects, `api-auth.setup.ts`, `helpers.ts`, and first specs covering the core endpoints (tokenize, translation, grammar, practice).
- **Add `mock_x_request.dart` fixtures + `http.MockClient` tests** in `test/pangea/` for each choreo repo, starting with the most-called endpoints.
- **Expand Playwright browser specs** — once mock mode is wired, specs can exercise LLM-backed flows without cost. Use the `write-e2e-test` skill and update `trigger-map.json`.
- **Flutter integration CI** — `integration_test/app_test.dart` is not in CI; needs a device/emulator runner. Low priority given Playwright covers the same flows.

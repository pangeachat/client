---
applyTo: "client/e2e/**"
---

# Running Playwright & axe-core Tests Locally

Step-by-step guide for running the client's Playwright functional tests and axe-core accessibility audits on a developer machine. Both run through the same Playwright test runner — axe-core audits are just another spec file ([`a11y.spec.ts`](../../e2e/scripts/a11y.spec.ts)). For test authoring conventions, see [authoring-playwright-and-axe-tests.instructions.md](authoring-playwright-and-axe-tests.instructions.md).

## Prerequisites

- **Node.js** (LTS)
- **Flutter SDK** (≥3.0) with Chrome/Chromium available
- A `client/.env` file with staging test credentials (see below)

## One-Time Setup

### 1. Install Node dependencies

From the `client/` root:

```bash
npm install
```

This installs `@playwright/test`, `@axe-core/playwright`, and `minimatch`.

### 2. Install Playwright browsers

```bash
npx playwright install chromium
```

### 3. Verify test credentials in `.env`

The Playwright config ([`e2e/playwright.config.ts`](../../e2e/playwright.config.ts)) auto-loads `client/.env`. The auth setup needs these three variables:

| Variable | Purpose | Example |
|---|---|---|
| `STAGING_TEST_EMAIL` | Login email for the test account | `wykuji@denipl.com` |
| `STAGING_TEST_PASSWORD` | Password for the test account | *(same as email for test accounts)* |
| `STAGING_TEST_USER` | Matrix user ID (informational) | `@wykuji:staging.pangea.chat` |

If your `.env` already has these from the standard `config.sample.json` setup, no extra config is needed.

## Running Tests

### Step 1 — Start the Flutter web app

In a separate terminal, start the Flutter web app on port **8080** (must match the Playwright config default):

```bash
cd client
flutter run -d chrome --web-port 8080
```

> ⚠️ Always use `--web-port 8080`. Without it, Flutter picks a random port and you'll need to pass `BASE_URL=http://localhost:<port>` to every test command.

### Step 2 — Run the tests

From the `client/` root:

```bash
# Run all tests (functional + accessibility)
npx playwright test --config e2e/playwright.config.ts

# Run only accessibility audits
npx playwright test e2e/scripts/a11y.spec.ts --config e2e/playwright.config.ts

# Run only functional tests (e.g. login)
npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts

# Run against staging deployment (no local Flutter needed)
BASE_URL=https://app.staging.pangea.chat npx playwright test --config e2e/playwright.config.ts
```

> The default command runs **everything** — login flow, accessibility audits, and any other specs in `e2e/scripts/`.

### Step 3 — View results

```bash
npx playwright show-report
```

Failed tests save screenshots to `test-results/`.

## Debugging

### Headed mode with Playwright Inspector

```bash
PWDEBUG=1 npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts
```

### Run a single test by name

```bash
npx playwright test --config e2e/playwright.config.ts -g "should display landing page"
```

## How It Works

1. **Env var loading**: [`playwright.config.ts`](../../e2e/playwright.config.ts) reads `client/.env` using a lightweight `fs`-based parser (no `dotenv` dependency). Shell env vars take precedence over `.env` values.

2. **`BASE_URL` resolution order**: shell env var → `client/.env` → default `http://localhost:8080`.

3. **Auth & semantics**: The config runs a `setup` project first (login + save session), then every spec reuses that session and auto-enables Flutter's semantics tree. For details on how auth state and semantics enablement work, see [authoring-playwright-and-axe-tests.instructions.md](authoring-playwright-and-axe-tests.instructions.md) § "Flutter-Playwright Patterns".

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `fill: value: expected string, got undefined` | `STAGING_TEST_EMAIL` or `STAGING_TEST_PASSWORD` not set | Verify they exist in `client/.env` (with values, not blank) |
| `browserType.launch: Executable doesn't exist` | Playwright browsers not installed or version mismatch | Run `npx playwright install chromium` |
| Login succeeds but `toHaveURL(/\/rooms/)` times out | Test account may need onboarding, or network is slow | Try increasing timeout; check account state manually |
| `Enable accessibility` button not found | Flutter app not fully loaded, or wrong URL | Verify the app is running and `BASE_URL` is correct |
| axe-core `aria-command-name` violations | Buttons missing accessible names | Add `tooltip:` to `IconButton` or `Semantics(label:)` wrapper in Flutter code |
| axe-core `role-img-alt` violations | Images missing alt text | Add `semanticLabel:` to the `Image` widget, or `excludeFromSemantics: true` if decorative |

## Future Work

_(No linked issues yet.)_

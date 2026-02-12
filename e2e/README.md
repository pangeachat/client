# Pangea Chat E2E Tests

Playwright-based end-to-end tests for the Pangea Chat web application.

## Prerequisites

- Node.js (LTS version)
- A running Flutter web app at `http://localhost:8080` or access to staging deployment

## Setup

1. Install dependencies:
   ```bash
   npm install
   npx playwright install chromium
   ```

2. Set environment variables:
   ```bash
   export TEST_USER="your-test-email@example.com"
   export TEST_PASSWORD="your-test-password"
   export BASE_URL="http://localhost:8080"  # or https://app.staging.pangea.chat
   ```

## Running Tests

### Run all tests
```bash
npx playwright test --config e2e/playwright.config.ts
```

### Run a specific test
```bash
npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts
```

### Run tests triggered by git diff
```bash
# Web tests only
node e2e/select-tests.js HEAD~1 --platform web | xargs npx playwright test --config e2e/playwright.config.ts

# Mobile tests only
node e2e/select-tests.js HEAD~1 --platform mobile

# All tests (web + mobile)
node e2e/select-tests.js HEAD~1 --platform all
```

### View test report
```bash
npx playwright show-report
```

## Architecture

- **`fixtures.ts`** — Shared test setup that enables Flutter's semantics tree
- **`auth.setup.ts`** — Authentication setup that runs once and saves login state
- **`playwright.config.ts`** — Playwright configuration
- **`scripts/*.spec.ts`** — Individual test scripts
- **`trigger-map.json`** — Maps file globs to test scripts for diff-based test selection
- **`select-tests.js`** — Script to select tests based on changed files

## Flutter Semantics

Flutter web renders to `<canvas>`, so Playwright can only interact with Flutter's **semantics tree** (accessibility tree). The `fixtures.ts` file automatically enables the semantics tree by clicking the `flt-semantics-placeholder` element on page load.

All interactive widgets in the Flutter app must have:
- `tooltip` on `IconButton`s
- `Semantics(label: '...', button: true)` wrapper for `GestureDetector`/`InkWell`
- Text content in `Text()` widgets

## CI Integration

In GitHub Actions, set secrets:
- `STAGING_TEST_USER`
- `STAGING_TEST_PASSWORD`

Map to environment variables:
```yaml
env:
  TEST_USER: ${{ secrets.STAGING_TEST_USER }}
  TEST_PASSWORD: ${{ secrets.STAGING_TEST_PASSWORD }}
  BASE_URL: https://app.staging.pangea.chat
```

## Writing Tests

1. Create a new spec file in `e2e/scripts/`
2. Import fixtures: `import { test, expect } from '../fixtures';`
3. Write test cases using Playwright's accessibility selectors:
   ```typescript
   await page.getByRole('button', { name: 'Button Text' }).click();
   await expect(page.getByText('Expected Text')).toBeVisible();
   ```
4. Add the test to `trigger-map.json` with file glob patterns

## Debugging

Run tests in headed mode with Playwright Inspector:
```bash
PWDEBUG=1 npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts
```

View accessibility tree:
```bash
npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts --debug
```

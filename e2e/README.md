# Pangea Chat E2E Tests

Playwright functional tests and axe-core accessibility audits for the Pangea Chat Flutter web app. This README is the runbook (install, run, debug, troubleshoot). Design contracts and lever-test rules live in [`playwright-testing.instructions.md`](../.github/instructions/playwright-testing.instructions.md); reach for that doc when something behaves unexpectedly, the README only covers mechanics.

## File Layout

```
e2e/
  fixtures.ts              # Shared fixture — enables Flutter semantics on each page load
  auth.setup.ts            # Logs in once, saves session (incl. IndexedDB) for all specs
  playwright.config.ts     # Config — loads .env, sets baseURL
  trigger-map.json         # Maps file globs → spec files for diff-based CI selection
  select-tests.js          # Diff-based test selector
  scripts/
    login.spec.ts          # Login flow
    a11y.spec.ts           # Accessibility audits (axe-core, WCAG 2.1 AA)
```

## Prerequisites

- **Node.js** (LTS)
- **Flutter SDK** (≥3.0) with Chrome/Chromium available
- A `client/.env` file with staging test credentials (see [Credentials](#credentials) below)

## One-time setup

```bash
# from the client/ root
npm install                          # installs @playwright/test, @axe-core/playwright, minimatch
npx playwright install chromium      # downloads the Chromium binary
```

## Credentials

The Playwright config auto-loads `client/.env`. The auth setup needs:

| Variable | Purpose |
|---|---|
| `TEST_MATRIX_USERNAME` | Matrix username (localpart, no `@` or domain) |
| `TEST_MATRIX_PASSWORD` | Password |

Both come from AWS Secrets Manager at `/staging/test-user/matrix-credentials`. `client/.env` is gitignored. Fetch the values one of these ways:

```sh
# A) From AWS Secrets Manager (preferred — requires staging SSO access)
aws sso login --profile PangeaChat                 # one-time per session
aws secretsmanager get-secret-value \
  --profile PangeaChat \
  --secret-id /staging/test-user/matrix-credentials \
  --query SecretString --output text \
  | jq -r '"TEST_MATRIX_USERNAME=\(.username)\nTEST_MATRIX_PASSWORD=\(.password)"' \
  >> .env

# B) From 2-step-choreographer/.env, which mirrors the same values
grep -E '^TEST_MATRIX_(USERNAME|PASSWORD)=' ../2-step-choreographer/.env >> .env
```

If neither path works, ask Will via a private channel.

## Running tests

In one terminal, start the Flutter web app on port **8080** (must match the Playwright config default):

```bash
cd client
flutter run -d chrome --web-port 8080
```

> Always use `--web-port 8080`. Without it, Flutter picks a random port and every test command needs `BASE_URL=http://localhost:<port>`.

Then in another terminal:

```bash
# Everything (functional + a11y)
npx playwright test --config e2e/playwright.config.ts

# A11y audits only
npx playwright test e2e/scripts/a11y.spec.ts --config e2e/playwright.config.ts

# Single spec
npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts

# Against deployed staging (no local Flutter needed)
BASE_URL=https://app.staging.pangea.chat npx playwright test --config e2e/playwright.config.ts

# Single test by name within a spec
npx playwright test --config e2e/playwright.config.ts -g "should display landing page"

# Headed with the Playwright Inspector
PWDEBUG=1 npx playwright test e2e/scripts/login.spec.ts --config e2e/playwright.config.ts

# View the last run's report
npx playwright show-report
```

Failed-run screenshots land in `test-results/`.

## How it works

1. **Env var loading**: `playwright.config.ts` reads `client/.env` with a lightweight `fs`-based parser (no `dotenv` dependency). Shell env vars take precedence.
2. **`BASE_URL` resolution**: shell env → `client/.env` → default `http://localhost:8080`.
3. **Setup project**: the config runs `auth.setup.ts` first (login + save session with `storageState({ indexedDB: true })`), then every spec reuses that session and the shared fixture auto-enables Flutter's semantics tree.
4. **Mock backend calls**: configure the client to send `mock=true` and `mock_llm_latency_override_s=0` on choreo requests. See [`playwright-testing.instructions.md` § Bypassing paid backend calls](../.github/instructions/playwright-testing.instructions.md#bypassing-paid-backend-calls---mocktrue) for the full contract.

## CI integration

CI fetches `TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD` from AWS Secrets Manager via GitHub OIDC — no GitHub-secret mirror. The workflow in [`.github/workflows/e2e-tests.yml`](../.github/workflows/e2e-tests.yml) assumes `AWS_ROLE_ARN_STAGING` and reads the `/staging/test-user/matrix-credentials` JSON secret with `parse-json-secrets: true`. The OIDC role's IAM grant lives in `devops/terraform/staging/iam/github-oidc/`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `fill: value: expected string, got undefined` | `TEST_MATRIX_USERNAME` / `PASSWORD` not set | Verify both exist in `client/.env` with non-empty values |
| `browserType.launch: Executable doesn't exist` | Playwright browsers not installed | `npx playwright install chromium` |
| Login succeeds but `toHaveURL(/\/rooms/)` times out | Test account state, or slow network | Bump timeout; check account state via the staging app |
| `Enable accessibility` button not found | Flutter app not fully loaded or wrong `BASE_URL` | Verify app is running and `BASE_URL` is correct |
| axe-core `aria-command-name` violations | Buttons missing accessible names | Add `tooltip:` to `IconButton` or wrap in `Semantics(label:)` |
| axe-core `role-img-alt` violations | Images missing alt text | Add `semanticLabel:` or `excludeFromSemantics: true` |
| Specs pass alone, fail in the suite | Auth state not restored — missing `indexedDB: true` | See [`playwright-testing.instructions.md` § Auth state persistence](../.github/instructions/playwright-testing.instructions.md#auth-state-persistence) |
| HTTP 500 from a choreo route under `mock=true` | Backend handler missing a mock producer | File against `pangeachat/2-step-choreographer` — see [`playwright-testing.instructions.md` § Bypassing paid backend calls](../.github/instructions/playwright-testing.instructions.md#bypassing-paid-backend-calls---mocktrue) |

## Adding coverage for a new flow

Use the [`write-e2e-test` skill](../.github/skills/write-e2e-test/SKILL.md) — it walks the procedure (semantics audit → widget labels → spec → axe coverage → trigger-map). Conventions and patterns are pinned in [`playwright-testing.instructions.md`](../.github/instructions/playwright-testing.instructions.md).

## Further reading

| Doc | Purpose |
|---|---|
| [`playwright-testing.instructions.md`](../.github/instructions/playwright-testing.instructions.md) | Design contracts — canvas/semantics, mock-mode, auth state, axe limits |
| [`pangea-automated-test-design.md`](pangea-automated-test-design.md) | Architecture and design rationale |
| [`web-and-accessibility-next-steps.md`](web-and-accessibility-next-steps.md) | Coverage matrix and backlog |

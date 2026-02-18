# Pangea Chat E2E Tests

Playwright functional tests and axe-core accessibility audits for the Pangea Chat Flutter web app.

## Quick Start (for QA)

### 1. Run existing tests locally

Follow the step-by-step setup guide:  
→ [run-playwright-and-axe-local.instructions.md](../.github/instructions/run-playwright-and-axe-local.instructions.md)

It covers installing dependencies, configuring credentials, starting the Flutter app, and running all tests (functional + accessibility).

### 2. Write new tests for a flow

Read the authoring conventions first, then use the guided skill:  
→ [authoring-playwright-and-axe-tests.instructions.md](../.github/instructions/authoring-playwright-and-axe-tests.instructions.md) — patterns, selectors, credential delivery  
→ [write-e2e-test/SKILL.md](../.github/skills/write-e2e-test/SKILL.md) — 9-step procedure for adding coverage to a new flow

### 3. See what still needs coverage

The coverage matrix tracks which flows have tests:  
→ [web-and-accessibility-next-steps.md](web-and-accessibility-next-steps.md)

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

## Key Concepts

- **Semantics tree**: Flutter renders to `<canvas>`. Playwright interacts via the accessibility tree, enabled by `fixtures.ts`. Widgets need `tooltip:`, `Semantics(label:)`, or text children to be testable.
- **Auth state**: `auth.setup.ts` saves login state including IndexedDB (`storageState({ indexedDB: true })`). All specs reuse it.
- **Diff-triggered CI**: `trigger-map.json` maps Dart source globs to spec files. On deploy, only affected specs run. Full suite runs nightly.

## CI Integration

GitHub Actions secrets:
- `STAGING_TEST_EMAIL` — test account email
- `STAGING_TEST_PASSWORD` — test account password

```yaml
env:
  STAGING_TEST_EMAIL: ${{ secrets.STAGING_TEST_EMAIL }}
  STAGING_TEST_PASSWORD: ${{ secrets.STAGING_TEST_PASSWORD }}
  BASE_URL: https://app.staging.pangea.chat
```

## Further Reading

| Doc | Purpose |
|---|---|
| [run-playwright-and-axe-local.instructions.md](../.github/instructions/run-playwright-and-axe-local.instructions.md) | Local setup, running, debugging, troubleshooting |
| [authoring-playwright-and-axe-tests.instructions.md](../.github/instructions/authoring-playwright-and-axe-tests.instructions.md) | Conventions, Flutter-Playwright patterns, axe-core rules |
| [pangea-automated-test-design.md](pangea-automated-test-design.md) | Architecture and design rationale |
| [web-and-accessibility-next-steps.md](web-and-accessibility-next-steps.md) | Coverage matrix and backlog |

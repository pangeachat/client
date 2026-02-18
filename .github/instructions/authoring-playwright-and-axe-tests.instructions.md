---
applyTo: "client/e2e/**,client/.github/workflows/e2e-*.yml,client/.github/workflows/copilot-setup-steps.yml,client/.github/agents/**,client/.github/skills/write-e2e-test/**"
---

# Authoring Playwright & axe-core Tests

> **Purpose**: Conventions and patterns for writing Playwright functional tests and axe-core accessibility audits against the Flutter web app. Auto-loaded when editing `e2e/` files.

- Running tests locally: [run-playwright-and-axe-local.instructions.md](run-playwright-and-axe-local.instructions.md)
- Design rationale: [`e2e/pangea-automated-test-design.md`](../../e2e/pangea-automated-test-design.md)

## File Layout

```
client/
  e2e/
    fixtures.ts               # Shared fixture — semantics enablement + navigation
    auth.setup.ts              # Login once, save session for all specs
    playwright.config.ts       # Config — loads .env, sets baseURL
    trigger-map.json           # Maps file globs → spec files for diff-based selection
    select-tests.js            # --platform web
    scripts/
      login.spec.ts            # Login flow spec
      a11y.spec.ts             # Accessibility audits (axe-core, WCAG 2.1 AA)
```

## Conventions

### Element selectors

Playwright identifies elements via Flutter's **semantics tree** (ARIA roles + names), not the canvas.

- Use `page.getByRole('button', { name: '...' })` — name comes from `tooltip` or `Semantics(label:)`
- Use `page.getByRole('textbox', { name: '...' })` for text fields
- Use `page.getByText('...')` for static text

### Widget requirements for testability

- All `IconButton`s **must** have `tooltip:`
- All tappable `GestureDetector`/`InkWell` should be wrapped in `Semantics(label:..., button: true)`
- Decorative images: `excludeFromSemantics: true`
- Meaningful images: `semanticLabel: '...'`

### Credential delivery

- **Local**: `STAGING_TEST_EMAIL` and `STAGING_TEST_PASSWORD` from `client/.env` (see [run-playwright-and-axe-local.instructions.md](run-playwright-and-axe-local.instructions.md))
- **CI**: GitHub Actions secrets `STAGING_TEST_EMAIL`, `STAGING_TEST_PASSWORD`

## Flutter-Playwright Patterns (critical)

Flutter renders to `<canvas>` — its semantics tree behaves differently from standard HTML. These patterns are required.

1. **Semantics enablement**: Flutter positions `flt-semantics-placeholder` **off-screen**. Use `dispatchEvent("click")` — regular `.click()` and `force: true` both fail. The shared fixture in [`fixtures.ts`](../../e2e/fixtures.ts) handles this automatically.

2. **Text input filling**: Canvas-based inputs need explicit `.click()` to focus before `.fill()`, with `waitForTimeout(500)` between fields. Without this, the first field's value gets lost when focus moves.

3. **Login timeout**: Matrix server round-trip takes up to 30s. Always use `{ timeout: 30000 }` on `toHaveURL(/\/rooms/)` after login.

4. **Responsive layout**: At headless Chromium's default viewport, the app renders a nav rail (Home, All chats, Settings) — NOT a header with a Search button. Assert against what the viewport actually shows.

5. **Test file imports**: All spec files import `{ test, expect }` from `../fixtures`, NOT from `@playwright/test`. The fixture handles navigation to `/` and semantics enablement — tests must NOT repeat this.

6. **Auth state with IndexedDB**: [`auth.setup.ts`](../../e2e/auth.setup.ts) saves state with `storageState({ path, indexedDB: true })`. Flutter's Matrix client stores session tokens in IndexedDB, not cookies/localStorage. Without `indexedDB: true`, authenticated tests can't restore the session.

## Accessibility Testing (axe-core)

[`a11y.spec.ts`](../../e2e/scripts/a11y.spec.ts) runs WCAG 2.1 AA audits using `@axe-core/playwright`. When adding a new flow spec, also add an axe-core audit for that flow's pages.

### How it works

- Audits are scoped to `flt-semantics-host` (Flutter's semantics overlay) — the canvas is opaque to axe
- Tags: `wcag2a`, `wcag2aa`, `wcag21aa`
- The shared `auditPage(page)` helper handles the AxeBuilder setup — navigate to the page and call it

### Auth state in a11y tests

- Unauthenticated pages: `test.use({ storageState: { cookies: [], origins: [] } })`
- Authenticated pages: inherit the saved auth state (including IndexedDB) from setup

### Zero-tolerance policy

Tests assert `violations.toHaveLength(0)`. Fix the widget — don't allowlist violations.

### What axe can't check (Flutter canvas limitation)

- **Color contrast** — axe can't inspect pixels inside `<canvas>`
- **Visual layout** — the rendered UI is canvas, not DOM

## Future Work

_(No linked issues yet.)_

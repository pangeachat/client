---
name: add-e2e-coverage
description: >-
  Add Playwright E2E and accessibility test coverage for a feature flow in the Pangea Chat Flutter web app.
  Walks through semantics audit, label fixes, spec authoring, axe-core accessibility auditing,
  trigger-map wiring, and validation.
  Use when asked to "write a Playwright test", "add an E2E test", "test [flow] end-to-end",
  or "add accessibility coverage".
---

# Add E2E & Accessibility Coverage

> **Purpose**: Step-by-step procedure for adding a new flow — invoked on demand by a developer asking Copilot to write a test.

You are adding end-to-end and accessibility test coverage for a flow in the Pangea Chat Flutter web app. The app renders to `<canvas>` — Playwright can only interact via the **semantics tree** (ARIA roles derived from tooltips, `Semantics` wrappers, and text children). You must audit and fix semantics gaps before writing the spec.

## Prerequisites

- Read `client/.github/instructions/e2e-testing.instructions.md` for conventions and Flutter-Playwright patterns
- Read `client/e2e/web-and-accessibility-next-steps.md` for the coverage matrix and status
- Read `client/e2e/fixtures.ts` to understand what the shared fixture already does (navigation to `/`, semantics enablement, 3s wait)

## Step-by-step procedure

### Step 1: Identify the flow

Ask the user which flow to test if not specified. Check the coverage matrix in `client/e2e/web-and-accessibility-next-steps.md` to see what already exists.

### Step 2: Audit semantics

Walk through the flow in the staging app using Playwright MCP's `browser_snapshot` (or have the user check DevTools → Accessibility tab). Look for:

- Buttons that show as unnamed `generic` or unlabeled `button` nodes
- Text fields without accessible names
- Tappable areas (GestureDetector, InkWell) with no ARIA role

### Step 3: Fix semantics gaps

For each unlabeled element:

| Widget                        | Fix                                                         |
| ----------------------------- | ----------------------------------------------------------- |
| `IconButton`                  | Add `tooltip:` parameter                                    |
| `GestureDetector` / `InkWell` | Wrap in `Semantics(label: '...', button: true, child: ...)` |
| Decorative `Image`            | Add `excludeFromSemantics: true`                            |
| Meaningful `Image`            | Add `semanticLabel: '...'`                                  |

**Critical**: Files outside `lib/pangea/` must wrap changes in `// #Pangea` / `// Pangea#` markers. Files inside `lib/pangea/` do not need markers.

Use existing L10n keys from `assets/l10n/intl_en.arb` where possible — check before creating new strings.

### Step 4: Write the spec

Create `client/e2e/scripts/<flow>.spec.ts`:

1. Import `{ test, expect }` from `../fixtures` — **never** from `@playwright/test`
2. The fixture already navigates to `/` and enables semantics — do NOT repeat this
3. Use `page.getByRole(...)` locators (not CSS selectors or XPath)
4. Follow the Flutter-Playwright patterns from the instructions (click-to-focus before fill, 500ms waits between fields, 30s login timeout)
5. If the test needs to start unauthenticated: `test.use({ storageState: { cookies: [], origins: [] } })`
6. Otherwise the test automatically uses the auth state saved by `auth.setup.ts`

### Step 5: Add accessibility coverage

Add an axe-core audit for the new flow's page(s) in `client/e2e/scripts/a11y.spec.ts`. The `auditPage()` helper is already defined — you just need to navigate to the page and call it:

```typescript
test("<page> has no a11y violations", async ({ page }) => {
  // Navigate to the page (fixture already goes to '/' and enables semantics)
  // ... click through to the target page ...
  await expect(page.getByRole("button", { name: "..." })).toBeVisible();

  const violations = await auditPage(page);
  expect(violations, formatViolations(violations)).toHaveLength(0);
});
```

Place the test in the appropriate `describe` block — `Unauthenticated pages` (with `test.use({ storageState: { cookies: [], origins: [] } })`) or `Authenticated pages`.

### Step 6: Wire up trigger-map

Add an entry to `client/e2e/trigger-map.json`:

```json
"<flow>": {
  "globs": ["lib/pangea/<relevant>/**", ...],
  "web": "scripts/<flow>.spec.ts",
  "mobile": null
}
```

Choose globs that match the Dart source files whose changes should trigger this test.

### Step 7: Run and validate

```bash
TEST_USER=$TEST_USER TEST_PASSWORD=$TEST_PASSWORD \
  npx playwright test --config e2e/playwright.config.ts e2e/scripts/<flow>.spec.ts
```

If the test fails:

- Check whether the failure is a missing semantics label (go back to Step 3)
- Check whether a timing issue needs a `waitForTimeout` or longer assertion timeout
- Check whether the responsive layout at default viewport differs from what you expected (nav rail vs. header)

### Step 8: Update coverage matrix

Mark the flow as ✅ in the Web column of `client/e2e/web-and-accessibility-next-steps.md`.

### Step 9: Commit

Commit the Dart semantics fixes and the new spec file together so they stay in sync. Include the trigger-map update and the plan update in the same commit.

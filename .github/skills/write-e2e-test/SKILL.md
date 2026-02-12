---
name: write-e2e-test
description: >-
  Write a new Playwright E2E test for a feature flow in the Pangea Chat Flutter web app.
  Walks through semantics audit, label fixes, spec authoring, trigger-map wiring, and validation.
  Use when asked to "write a Playwright test", "add an E2E test", or "test [flow] end-to-end".
---

# Write a Playwright E2E Test

You are adding a new end-to-end test for the Pangea Chat Flutter web app. The app renders to `<canvas>` — Playwright can only interact via the **semantics tree** (ARIA roles derived from tooltips, `Semantics` wrappers, and text children). You must audit and fix semantics gaps before writing the spec.

## Prerequisites

- Read `client/.github/instructions/e2e-testing.instructions.md` for conventions and Flutter-Playwright patterns
- Read `client/test/pangea/playwright-test-plan.md` for the coverage matrix and status
- Read `client/e2e/fixtures.ts` to understand what the shared fixture already does (navigation to `/`, semantics enablement, 3s wait)

## Step-by-step procedure

### Step 1: Identify the flow

Ask the user which flow to test if not specified. Check the coverage matrix in `client/test/pangea/playwright-test-plan.md` to see what already exists.

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

### Step 5: Wire up trigger-map

Add an entry to `client/e2e/trigger-map.json`:

```json
"<flow>": {
  "globs": ["lib/pangea/<relevant>/**", ...],
  "web": "scripts/<flow>.spec.ts",
  "mobile": null
}
```

Choose globs that match the Dart source files whose changes should trigger this test.

### Step 6: Run and validate

```bash
TEST_USER=$TEST_USER TEST_PASSWORD=$TEST_PASSWORD \
  npx playwright test --config e2e/playwright.config.ts e2e/scripts/<flow>.spec.ts
```

If the test fails:

- Check whether the failure is a missing semantics label (go back to Step 3)
- Check whether a timing issue needs a `waitForTimeout` or longer assertion timeout
- Check whether the responsive layout at default viewport differs from what you expected (nav rail vs. header)

### Step 7: Update coverage matrix

Mark the flow as ✅ in the Web column of `client/test/pangea/playwright-test-plan.md`.

### Step 8: Commit

Commit the Dart semantics fixes and the new spec file together so they stay in sync. Include the trigger-map update and the plan update in the same commit.

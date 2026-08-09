---
name: add-e2e-coverage
description: >-
  Add Playwright E2E and accessibility test coverage for a feature flow in the Pangea Chat Flutter web app.
  Use when asked to "write a Playwright test", "add an E2E test", "test [flow] end-to-end",
  or "add accessibility coverage".
---

# Add E2E & Accessibility Coverage

**MUST READ** [`.github/instructions/playwright-testing.instructions.md`](../../instructions/playwright-testing.instructions.md) for the canvas/semantics constraints, widget testability rules, mock-mode contract, auth-state requirements, and axe limits before touching anything.

**MUST READ** [`e2e/README.md`](../../../e2e/README.md) for install / run / debug commands and the credentials fetch.

## Operational steps

1. **Pick a flow.** If the user didn't name one, check [`e2e/web-and-accessibility-next-steps.md`](../../../e2e/web-and-accessibility-next-steps.md) for the coverage matrix and ask.
2. **Audit semantics.** Run the flow in the staging app via Playwright MCP's `browser_snapshot` (or DevTools → Accessibility). Note every unlabelled button, text field, gesture detector, or image. Fix in Dart per the widget rules in `playwright-testing.instructions.md`.
3. **Add the spec.** Create `e2e/scripts/<flow>.spec.ts`. Import `{ test, expect }` from `../fixtures` (never `@playwright/test`). Use `page.getByRole(...)`. If the test starts unauthenticated, set `test.use({ storageState: { cookies: [], origins: [] } })`.
4. **Add the axe audit.** In `e2e/scripts/a11y.spec.ts`, add a `test("<page> has no a11y violations", ...)` block that navigates to the new page and calls the shared `auditPage(page)` helper. Place it in `Unauthenticated pages` or `Authenticated pages`.
5. **Wire `e2e/trigger-map.json`.** Map the Dart-source globs that should re-trigger this spec on diff-based CI runs.
6. **Run locally.** Per the README's "Running tests" section.
7. **Update the coverage matrix.** Mark the flow as ✅ in `e2e/web-and-accessibility-next-steps.md`.
8. **Commit Dart semantics fixes + spec + a11y test + trigger-map + coverage update together** so the wiring stays consistent in a single revert if needed.

## Refusals

- Do not allowlist axe violations to make a test pass — fix the widget instead.
- Do not write a spec that imports `{ test, expect }` from `@playwright/test` directly — it skips the shared fixture and the run sees an empty semantics tree.
- Do not work around a choreo `mock=true` 500 on the client side — the fix belongs in `pangeachat/2-step-choreographer` per the contract.

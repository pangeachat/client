# Next Steps — Playwright (Web) & Accessibility Coverage

> **Purpose**: Actionable backlog for web E2E and axe-core accessibility coverage — _what's_ done, what's next, and the coverage matrix. The living checklist.

Architecture and long-term design: [pangea-automated-test-design.md](pangea-automated-test-design.md)
Mobile (Patrol) plan: [mobile-testing-plan.md](mobile-testing-plan.md)

## Major todos

- [ ] Add integration testing
- [ ] Add a11y testing and fix violations
- [ ] Test the cloud agent (`e2e-tester`) with a real failure issue
- [ ] Use the `add-e2e-coverage` skill to author a spec beyond login

---

## Build status

| Phase             | Description                                                       | Status                                 |
| ----------------- | ----------------------------------------------------------------- | -------------------------------------- |
| 1. Semantics      | Tooltips and `Semantics` wrappers so Playwright can find elements | Login flow done, most of app remaining |
| 2. Infrastructure | Config, fixtures, auth, trigger map, test selector                | ✅                                     |
| 3. CI/CD          | Workflow, Copilot setup steps, agent profile, skill               | ✅                                     |
| 4. More web specs | Remaining `*.spec.ts` for each flow                               | ✅                                     |

For mobile (Patrol) status, see [mobile-testing-plan.md](mobile-testing-plan.md).

For file layout and infrastructure details, see the [README](README.md) and [playwright-testing.instructions.md](../.github/instructions/playwright-testing.instructions.md).

---

## Web test flows & coverage

Each flow maps to a Playwright spec via `e2e/trigger-map.json`.

| Flow                        | Status | Notes                |
| --------------------------- | :----: | -------------------- |
| Login                       |   ✅   |                      |
| Accessibility (axe-core)    |   ✅   |                      |
| Course and chat navigation  |   ✅   |                      |
| Settings                    |   ✅   |                      |
| Analytics                   |   ✅   |                      |
| Logout                      |   ✅   |                      |

### Adding a new flow

Pick a flow from the table above (or add a new row), then invoke the `add-e2e-coverage` skill (`.github/skills/write-e2e-test/SKILL.md`). Ask Copilot something like _"add E2E coverage for the settings flow"_ and it will walk through the 9-step procedure: semantics audit → fixes → spec → a11y coverage → trigger-map → validation → commit.

---

## Outstanding axe-core violations

For how axe-core audits work, see [playwright-testing.instructions.md § What axe can't check](../.github/instructions/playwright-testing.instructions.md#what-axe-cant-check).

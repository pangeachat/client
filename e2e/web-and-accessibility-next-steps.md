# Next Steps — Playwright (Web) & Accessibility Coverage

> **Purpose**: Actionable backlog for web E2E and axe-core accessibility coverage — _what's_ done, what's next, and the coverage matrix. The living checklist.

Architecture and long-term design: [pangea-automated-test-design.md](pangea-automated-test-design.md)
Mobile (Patrol) plan: [mobile-testing-plan.md](mobile-testing-plan.md)

## Major todos

- [ ] Fix the 2 axe-core violations on the chat list page (see § "Example violations" below)
- [ ] Add semantics coverage to remaining flows (message toolbar, course discovery, settings, analytics)
- [ ] Write Playwright specs for remaining flows (see coverage table below)
- [ ] Test the cloud agent (`e2e-tester`) with a real failure issue
- [ ] Use the `add-e2e-coverage` skill to author a spec beyond login

---

## Build status

| Phase             | Description                                                       | Status                                 |
| ----------------- | ----------------------------------------------------------------- | -------------------------------------- |
| 1. Semantics      | Tooltips and `Semantics` wrappers so Playwright can find elements | Login flow done, most of app remaining |
| 2. Infrastructure | Config, fixtures, auth, trigger map, test selector                | ✅                                     |
| 3. CI/CD          | Workflow, Copilot setup steps, agent profile, skill               | ✅                                     |
| 4. More web specs | Remaining `*.spec.ts` for each flow                               | ⬜                                     |

For mobile (Patrol) status, see [mobile-testing-plan.md](mobile-testing-plan.md).

For file layout and infrastructure details, see the [README](README.md) and [playwright-testing.instructions.md](../.github/instructions/playwright-testing.instructions.md).

---

## Semantics work remaining

Only the login flow has full semantics coverage so far. Before writing a spec for a new flow, use the `add-e2e-coverage` skill (Steps 2–3) to audit and fix unlabeled widgets.

---

## Web test flows & coverage

Each flow maps to a Playwright spec via `e2e/trigger-map.json`.

| Flow                        | Status | Notes                |
| --------------------------- | :----: | -------------------- |
| Login                       |   ✅   |                      |
| Accessibility (axe-core)    |   ✅   |                      |
| Chat list navigation        |   ✅   |                      |
| Message toolbar (TTS, etc.) |   ✅   |                      |
| Course discovery            |   ✅   |                      |
| Settings                    |   ⬜   | Needs semantics work |
| Analytics                   |   ⬜   | Needs semantics work |
| Create DM                   |   ⬜   |                      |
| Logout                      |   ⬜   |                      |

### Adding a new flow

Pick a flow from the table above (or add a new row), then invoke the `add-e2e-coverage` skill (`.github/skills/write-e2e-test/SKILL.md`). Ask Copilot something like _"add E2E coverage for the settings flow"_ and it will walk through the 9-step procedure: semantics audit → fixes → spec → a11y coverage → trigger-map → validation → commit.

---

## Outstanding axe-core violations

For how axe-core audits work, see [playwright-testing.instructions.md § What axe can't check](../.github/instructions/playwright-testing.instructions.md#what-axe-cant-check).

### Example violations (first ones to fix)

> _Remove this section once these violations are resolved._

These were caught on the chat list page during initial testing. They are representative of the kinds of errors axe-core surfaces and are the first ones that need fixing:

**1. `aria-command-name` (serious) — Icon buttons without accessible names**

- 4 buttons with `role="button"` but no `aria-label`, visible text, or title
- Nodes: 44×44px and 18×18px icon buttons in the chat list header/app bar
- Fix: Add `tooltip:` to the `IconButton` widgets, or wrap in `Semantics(label: '...')`. The tooltip value becomes the ARIA label in the semantics tree.
- Rule: https://dequeuniversity.com/rules/axe/4.11/aria-command-name

**2. `role-img-alt` (serious) — Image missing alternative text**

- 1 image element (250×258px) with `role="img"` but no alt text — likely the empty chat list illustration
- Fix: Add `semanticsLabel:` to the `Image` / `SvgPicture` widget (same pattern used to fix `PangeaLogoSvg`)
- Rule: https://dequeuniversity.com/rules/axe/4.11/role-img-alt

### Already fixed

- **`PangeaLogoSvg`** — Added `semanticsLabel: 'Pangea Chat logo'` to `SvgPicture.asset()` in `lib/pangea/common/widgets/pangea_logo_svg.dart`. This resolved a `role-img-alt` violation on the landing page and email login page.
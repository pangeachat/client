# Pangea Automated Test Design

> **Purpose**: Architecture and rationale — _why_ we made the decisions we made. Read by humans for onboarding and context.

Related:

- Web & accessibility: [web-and-accessibility-next-steps.md](web-and-accessibility-next-steps.md)
- Mobile: [mobile-testing-plan.md](mobile-testing-plan.md)
- Conventions & patterns: [authoring-playwright-and-axe-tests.instructions.md](../.github/instructions/authoring-playwright-and-axe-tests.instructions.md)
- Running locally: [run-playwright-and-axe-local.instructions.md](../.github/instructions/run-playwright-and-axe-local.instructions.md)
- Guided authoring procedure: [write-e2e-test/SKILL.md](../.github/skills/write-e2e-test/SKILL.md)
- Cloud agent profile: [e2e-tester.md](../.github/agents/e2e-tester.md)

---

## Goals

1. **Regular, automated testing of main flows** — free up QA time for specific, fine-grained testing by automating coverage of login, messaging, course discovery, and other core user journeys.
2. **Regular, automated accessibility auditing** — use standardized frameworks (axe-core / WCAG 2.1 AA) to catch and prevent accessibility regressions across every deploy.

---

## Components

| Component             | File                                                                      | Role                                                                                                    | Status                                        |
| --------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **Deterministic CI**  | `.github/workflows/e2e-tests.yml`                                         | Runs Playwright on every deploy, nightly, and manual dispatch. Includes flow tests and axe-core audits. | ✅ Login + a11y specs pass. More specs needed |
| **Guided authoring**  | `.github/skills/write-e2e-test/SKILL.md`                                  | 9-step procedure for writing a new spec with Copilot (semantics audit → spec → trigger-map).            | ✅ Exists. Not yet used beyond login          |
| **Cloud agent**       | `.github/agents/e2e-tester.md`                                            | Copilot coding agent — assigned issues to write or fix specs via Playwright MCP, opens a PR.            | ✅ Profile exists. Untested                   |
| **Agent environment** | `.github/workflows/copilot-setup-steps.yml`                               | Installs Node + Playwright in the Copilot coding agent's sandbox.                                       | ✅                                            |
| **Conventions**       | `.github/instructions/authoring-playwright-and-axe-tests.instructions.md` | Auto-loaded when editing `e2e/` files — Flutter-Playwright patterns, file layout, semantics rules.      | ✅                                            |

---

## CI modes

All test types (flow specs and axe-core audits) run through the same workflow and modes.

| Mode      | Trigger                      | What runs                                |
| --------- | ---------------------------- | ---------------------------------------- |
| **Smoke** | Manual                       | `login` only                             |
| **Diff**  | After `Main Deploy Workflow` | Scripts matching changed files + `login` |
| **Full**  | Nightly (6am UTC) / manual   | All scripts                              |

Mobile CI will follow the same mode structure once Patrol is set up.

---

## Platform strategy

| Platform    | Tool                        | How it finds elements                  | Runs against                   | CI trigger                   |
| ----------- | --------------------------- | -------------------------------------- | ------------------------------ | ---------------------------- |
| **Web**     | Playwright Test             | ARIA roles from Flutter semantics tree | Live staging deploy            | Post-deploy, nightly, manual |
| **Android** | Patrol + `integration_test` | Text content, widget type, icon        | Emulator or Firebase Test Lab  | TBD                          |
| **iOS**     | Patrol + `integration_test` | Text content, widget type, icon        | Simulator or Firebase Test Lab | TBD                          |

Web is the foundation. Mobile shares the same `trigger-map.json` (each entry has `web` and `mobile` fields) but uses a completely different test runner.

---

## Web architecture (Playwright)

### Why semantics matter

Flutter's `<canvas>` is opaque to Playwright. Flutter exposes an optional **semantics tree** — an accessibility layer that creates hidden DOM nodes with ARIA roles. Playwright reads these nodes to locate elements like `button "Login"` or `textbox "Password"`.

Widgets without tooltips, text children, or `Semantics` wrappers appear as unnamed `generic` nodes and can't be targeted. Expanding coverage to a new flow always starts with auditing and fixing these gaps.

For implementation details (fixture mechanics, selectors, credential delivery): see [authoring-playwright-and-axe-tests.instructions.md](../.github/instructions/authoring-playwright-and-axe-tests.instructions.md).

### Diff-triggered test selection

`trigger-map.json` maps Dart source globs to spec files. On deploy, `select-tests.js` diffs the commit range against globs using `minimatch`, collects matching spec paths, and always includes `login`. CI runs only the matched set.

---

## Mobile architecture (Patrol) — future

Patrol extends Flutter's `integration_test` framework with native OS automation (permissions dialogs, system UI, push notifications, backgrounding). It does **not** need the semantics tree — it accesses the widget tree directly.

### Key decisions

- **Finders**: text-based (`$('Login')`) and type-based (`find.byType(ChatView)`) — matching existing `app_test.dart` style. Do NOT add `ValueKey`s.
- **App launch**: call `app.main()` directly — Patrol's binding replaces `IntegrationTestWidgetsFlutterBinding` before `main()` runs. Do NOT refactor `main.dart`.
- **Backend target**: `--dart-define=SYNAPSE_URL=...` — reads via `Environment.synapseURL`, no code change needed.
- **Credentials**: `--dart-define=TEST_USER=...` at compile time, sourced from GitHub Actions secrets in CI.
- **Shared infrastructure**: Web and mobile share `trigger-map.json`, `select-tests.js`, GitHub Actions secrets, and the staging backend.

Migration steps and file layout: [mobile-testing-plan.md](mobile-testing-plan.md)

---

## Development guidelines

These principles keep implementations consistent as new tests and flows are added:

- **Test against live deployments** — web tests hit staging (`app.staging.pangea.chat`). Mobile tests hit staging or a local homeserver via `--dart-define`. Local debug runs are useful for authoring but CI always targets a real deploy.
- **Diff-triggered by default** — only affected tests run on deploy; full suite runs nightly. See § "Diff-triggered test selection" below.
- **Semantics-first for web** — every testable widget needs a tooltip, `Semantics` wrapper, or text child. See § "Why semantics matter" below.
- **No widget Keys for testing** — Patrol uses text-based and type-based finders. Playwright uses ARIA roles. Neither requires adding `ValueKey`s to the widget tree.
- **Copilot-assisted authoring** — New tests are written with the `add-e2e-coverage` skill (local) or the `e2e-tester` agent (cloud). The infrastructure is designed to make both paths work.

---

## Accessibility testing (axe-core)

The semantics work for Playwright testing is the same work that makes the app accessible to screen readers. We run `@axe-core/playwright` (WCAG 2.1 AA) in the same CI pipeline — same browser session, no extra infrastructure.

**Zero-tolerance policy**: tests assert zero violations. Fix the widget, don't allowlist. This keeps the semantics tree clean for both Playwright locators and real screen readers.

axe can't check color contrast or visual layout inside Flutter's `<canvas>` — only the semantics overlay is auditable.

Implementation details, `auditPage()` helper usage, and auth-state patterns: see [authoring-playwright-and-axe-tests.instructions.md](../.github/instructions/authoring-playwright-and-axe-tests.instructions.md) § "Accessibility Testing (axe-core)".

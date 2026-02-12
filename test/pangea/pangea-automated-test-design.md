# Pangea Automated Test Design

Stable architecture spec for end-to-end testing across all platforms. The actionable ticket with current status and step-by-step instructions lives in [playwright-test-plan.md](playwright-test-plan.md).

---

## Principles

1. **Tests run against live deploys** — no local builds in CI. Web tests hit staging (`app.staging.pangea.chat`). Mobile tests hit staging or a local homeserver via `--dart-define`.
2. **Diff-triggered by default** — `trigger-map.json` maps source globs to test scripts. Only affected tests run on deploy. Full suite runs nightly.
3. **Semantics-first for web** — Flutter renders to `<canvas>`. Playwright interacts via the ARIA semantics tree, not DOM elements. Every testable widget needs a tooltip, `Semantics` wrapper, or text child.
4. **No widget Keys for testing** — Patrol uses text-based and type-based finders. Playwright uses ARIA roles. Neither requires adding `ValueKey`s to the widget tree.
5. **Copilot-assisted authoring** — New tests are written with the `write-e2e-test` skill (local) or the `e2e-tester` agent (cloud). The infrastructure is designed to make both paths work.

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

Semantics must be explicitly enabled per page load (the `flt-semantics-placeholder` button is positioned off-screen and requires `dispatchEvent("click")`). The shared fixture handles this.

Widgets without tooltips, text children, or `Semantics` wrappers appear as unnamed `generic` nodes and can't be targeted. Expanding coverage to a new flow always starts with auditing and fixing these gaps.

### Diff-triggered test selection

`trigger-map.json` is the single source of truth:

```json
{
  "login": {
    "globs": ["lib/pangea/login/**", "lib/pages/homeserver_picker.dart"],
    "web": "scripts/login.spec.ts",
    "mobile": null
  }
}
```

On deploy, `select-tests.js` diffs the commit range against globs using `minimatch`, collects matching spec paths, and always includes `login`. CI runs only the matched set.

### Credential delivery

- **Local**: shell env vars `TEST_USER`, `TEST_PASSWORD`, `BASE_URL`
- **CI**: GitHub Actions secrets `STAGING_TEST_USER`, `STAGING_TEST_PASSWORD`
- **Cloud agent**: `copilot` environment secrets `STAGING_TEST_EMAIL`, `STAGING_TEST_PASSWORD`

---

## Mobile architecture (Patrol) — future

Patrol extends Flutter's `integration_test` framework with native OS automation (permissions dialogs, system UI, push notifications, backgrounding). It does **not** need the semantics tree — it accesses the widget tree directly.

### Key decisions

- **Finders**: text-based (`$('Login')`) and type-based (`find.byType(ChatView)`) — matching existing `app_test.dart` style
- **App launch**: call `app.main()` directly — Patrol's binding replaces `IntegrationTestWidgetsFlutterBinding` before `main()` runs
- **Backend target**: `--dart-define=SYNAPSE_URL=...` for staging or local homeserver (reads via `Environment.synapseURL`)
- **Credentials**: `--dart-define=TEST_USER=...` at compile time, sourced from GitHub Actions secrets in CI

### File layout

```
integration_test/
  app_test.dart              # Existing FluffyChat integration tests
  patrol/
    common.dart              # Shared login helper
    login_test.dart          # Basic login validation
    send_message_test.dart
    permissions_test.dart    # Native permission dialogs
    ...
```

### Migration path

1. Install Patrol: `flutter pub add patrol --dev`, configure `pubspec.yaml` patrol section, native side setup (Android `AndroidManifest.xml`, iOS test runner)
2. Write `integration_test/patrol/common.dart` — shared login helper using `$('Login')` finders
3. Write `login_test.dart` to validate wiring end-to-end
4. Incrementally migrate existing `app_test.dart` flows to Patrol format
5. Add native-only tests (permissions, push notifications, backgrounding)
6. Add mobile CI workflow — start with Android emulator in GitHub Actions, graduate to Firebase Test Lab

### Shared infrastructure

Web and mobile share:

- `trigger-map.json` — each entry's `mobile` field points to a Patrol test (or `null`)
- `select-tests.js` — accepts `--platform web|mobile|all` flag
- Same GitHub Actions secrets for credentials
- Same staging backend target

---

## CI modes

| Mode      | Trigger                                         | What runs                              |
| --------- | ----------------------------------------------- | -------------------------------------- |
| **Smoke** | Manual dispatch                                 | Login only                             |
| **Diff**  | Post-deploy (chains off "Main Deploy Workflow") | Scripts matching changed files + login |
| **Full**  | Nightly (6am UTC) or manual                     | All scripts                            |

Mobile CI will follow the same mode structure once Patrol is set up.

---

## Copilot integration

| Layer                 | Component                     | Purpose                                                                                          |
| --------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------ |
| **Conventions**       | `e2e-testing.instructions.md` | Passively loaded when editing `e2e/` files — patterns, file layout, semantics rules              |
| **Guided authoring**  | `write-e2e-test/SKILL.md`     | Developer invokes to write a new spec — walks through semantics audit → spec → trigger-map       |
| **Cloud agent**       | `e2e-tester.md` agent profile | Assigned issues to write or fix specs autonomously — uses Playwright MCP to walk the staging app |
| **Agent environment** | `copilot-setup-steps.yml`     | Installs Node + Playwright in the Copilot coding agent sandbox                                   |

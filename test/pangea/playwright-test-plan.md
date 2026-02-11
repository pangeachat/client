# E2E Test Plan — Web (Playwright) & Mobile (Patrol)

## Goal

End-to-end coverage across **all platforms** the app ships on:

| Platform          | Tool                        | Runs against                                    |
| ----------------- | --------------------------- | ----------------------------------------------- |
| **Web**           | Playwright (MCP + Test)     | Live staging deploy (`app.staging.pangea.chat`) |
| **Android / iOS** | Patrol + `integration_test` | Emulators / real devices / Firebase Test Lab    |

**Web tests** use Playwright MCP against the live staging deployment — no local dev server needed.

Each test flow is a standalone **script** with a declared set of file-path triggers. When a release diff touches files matching a script's triggers, that script should run.

## Prerequisites

- Playwright MCP connected in VS Code
- Flutter semantics enabled (click the accessibility placeholder on page load)

### Credentials

Test credentials are **never stored in this file**. They are supplied by:

| Context                 | Source                                                                                              |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| Interactive (developer) | User provides credentials at session start, or references `cross-service-debugging.instructions.md` |
| CI/CD pipeline          | GitHub Actions secrets: `STAGING_TEST_USER`, `STAGING_TEST_PASSWORD`                                |

Scripts below use placeholders `$TEST_USER` and `$TEST_PASSWORD`.

### Environment

| Variable             | Value                                |
| -------------------- | ------------------------------------ |
| `STAGING_APP_URL`    | `https://app.staging.pangea.chat`    |
| `STAGING_API_URL`    | `https://api.staging.pangea.chat`    |
| `STAGING_MATRIX_URL` | `https://matrix.staging.pangea.chat` |

## Constraints

Flutter web renders to a `<canvas>`. Playwright can only interact with Flutter's **semantics tree**, which maps to ARIA attributes. This means:

1. Every interactive widget needs an accessible name (tooltip, text child, or `Semantics` label)
2. Canvas-based visuals (animations, colors, SVG decorations) are invisible to Playwright
3. Text content inside `Text()` widgets IS visible if the semantics tree is enabled
4. `GestureDetector` and `InkWell` without a `Semantics` wrapper appear as unnamed `generic` nodes

---

## Phase 1: Semantics Improvements (Pre-Requisite)

Add tooltips and `Semantics` labels so Playwright can identify all interactive elements. Priority order:

### P0 — Blocks all test flows

| Area             | What to fix                                                                                                      | Files                                                                 |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Landing page     | Settings `IconButton` missing tooltip                                                                            | `lib/pangea/login/pages/login_or_signup.dart`                         |
| Login email page | Password visibility toggle missing tooltip                                                                       | `lib/pages/login/login.dart`                                          |
| Chat list items  | `ListTile` and action icons have no semantic labels — rooms show as unnamed `generic` + unlabeled `button` nodes | `lib/pages/chat_list/chat_list_item.dart`                             |
| Chat list header | Search `IconButton` missing tooltip                                                                              | `lib/pages/chat_list/chat_list_header.dart`                           |
| Chat input bar   | Send button, attachment button, emoji button — some missing tooltips                                             | `lib/pages/chat/input_bar.dart`, `lib/pages/chat/chat_input_row.dart` |
| Nav rail items   | `GestureDetector` wrapper has no semantic label (tooltip exists but isn't on the tappable node)                  | `lib/pangea/chat_list/widgets/navi_rail_item.dart`                    |

### P1 — Blocks specific feature flows

| Area              | What to fix                                              | Files                                                          |
| ----------------- | -------------------------------------------------------- | -------------------------------------------------------------- |
| Message toolbar   | Word card, practice, translation buttons need tooltips   | `lib/pangea/toolbar/widgets/`                                  |
| Choreographer     | IGC accept/reject buttons, IT option buttons need labels | `lib/pangea/choreographer/widgets/`                            |
| Course discovery  | Course tiles need semantic labels with course name       | `lib/pangea/course_creation/widgets/`                          |
| Settings          | Unlabeled `IconButton`s across settings sub-pages        | `lib/pages/settings/`                                          |
| Activity sessions | Start, skip, submit buttons need tooltips                | `lib/pangea/activity_sessions/`                                |
| Analytics         | Construct tiles, practice buttons                        | `lib/pangea/analytics_page/`, `lib/pangea/analytics_practice/` |

### P2 — Nice-to-have for richer assertions

| Area              | What to fix                                                 |
| ----------------- | ----------------------------------------------------------- |
| Images/SVGs       | Add `semanticLabel` to `Image.asset()`, `SvgPicture`        |
| Decorative icons  | Add `excludeFromSemantics: true` to purely decorative icons |
| Dialog titles     | Ensure `AlertDialog` titles appear in semantics tree        |
| Snackbar messages | Wrap in `Semantics` for toast verification                  |

---

## Phase 2: Test Scripts

Each script is a self-contained Playwright MCP flow. Scripts declare **triggers** — glob patterns for files that, when changed in a release diff, indicate the script should run. Every script begins with a shared login preamble. Below are some examples to be fleshed out in separate files.

### Preamble (shared by all scripts)

```
1. Navigate to $STAGING_APP_URL
2. Enable accessibility (click semantics placeholder via page.evaluate)
3. Click "Login to my account"
4. Click "Email"
5. Fill "Username or email" → $TEST_USER
6. Fill "Password" → $TEST_PASSWORD
7. Click "Login"
8. Assert: URL contains /rooms
```

---

### Script: `login`

**Triggers:**

```
lib/pangea/login/**
lib/pages/login/**
lib/config/routes.dart
lib/widgets/matrix.dart
```

**Steps:**

```
1. (Preamble)
2. Assert: "Home" nav button visible
3. Assert: chat list items visible
```

---

### Script: `open-chat`

**Triggers:**

```
lib/pages/chat/**
lib/pages/chat_list/chat_list_item.dart
lib/pangea/chat_list/**
```

**Steps:**

```
1. (Preamble)
2. Click a chat room by name
3. Assert: URL contains /rooms/<roomid>
4. Assert: message list visible
5. Assert: input bar visible with text field
6. Click "Back" or nav to return to chat list
```

---

### Script: `create-dm`

**Triggers:**

```
lib/pages/new_private_chat/**
lib/pangea/chat_list/**
```

**Steps:**

```
1. (Preamble)
2. Click "Direct Message" FAB button
3. Assert: new private chat page loads
4. Type a username to search
5. Select a user from results
6. Assert: chat opens or confirmation appears
```

---

## Phase 3: Execution Model

There are three ways to run Playwright against a Flutter web app, and they serve different purposes. We'll use a **layered approach**: an agent generates deterministic test files, and then those test files run unattended in CI.

### Option A: Agent-driven (Playwright MCP) — exploratory / authoring

An LLM agent (Copilot, Claude, etc.) drives the browser interactively via Playwright MCP tools. The agent reads the accessibility snapshot, decides what to click, and asserts results in real time.

**Best for:**

- Writing and debugging new test scripts
- Exploratory testing of unfamiliar flows
- Self-healing when UI changes break locators (agent can adapt)
- One-off developer-triggered sessions

**Not suitable for CI** because it requires an LLM in the loop (slow, expensive, non-deterministic).

### Option B: Deterministic tests (Playwright Test) — CI / regression

Standard Playwright test files (`*.spec.ts`) that run headlessly with `npx playwright test`. No LLM needed. Fast, repeatable, free.

**Best for:**

- CI pipelines (GitHub Actions)
- Regression testing on every deploy
- Nightly full-suite runs

### Option C: Agent writes deterministic tests (hybrid) ← **recommended starting point**

Use Option A to _author_ the tests, then commit the generated `*.spec.ts` files. CI runs them via Option B.

```
Developer / Agent (one-time per flow)        CI (every deploy)
┌──────────────────────────────┐    ┌──────────────────────────────┐
│ 1. Agent opens staging app   │    │ 1. Checkout repo             │
│ 2. Walks through flow via    │    │ 2. npm ci && npx playwright  │
│    Playwright MCP            │    │    install                   │
│ 3. MCP --codegen=typescript  │    │ 3. Compute diff, select      │
│    emits *.spec.ts code      │    │    matching test files       │
│ 4. Developer reviews, edits, │    │ 4. npx playwright test       │
│    commits the spec file     │    │    <selected files>          │
└──────────────────────────────┘    │ 5. Upload report artifact    │
                                    └──────────────────────────────┘
```

Playwright MCP has a `--codegen=typescript` flag that emits TypeScript test code as the agent interacts. This is the bridge between agent exploration and deterministic CI.

### Option D: Cloud agent with Playwright (GitHub Copilot coding agent) ← **future goal**

GitHub's Copilot coding agent runs autonomously in a GitHub Actions-powered cloud environment. It can be extended with MCP servers — including Playwright MCP — to give the cloud agent browser access.

This is the most powerful option: a cloud-hosted LLM agent that can both browse the staging app _and_ commit fixes or updated test files, all without a developer's local machine.

**How it works:**

```
1. Create a GitHub issue or assign @copilot from a PR
   e.g., "Test the send-message flow on staging. If tests fail, fix the locators."

2. Copilot coding agent spins up in a GitHub Actions runner with:
   - Playwright MCP configured (browser access to staging)
   - Access to the repo's code (read/write on copilot/* branches)
   - Custom instructions from .github/agents/ and copilot-instructions.md

3. The agent:
   a. Opens staging app via Playwright MCP
   b. Walks through the flow described in the issue
   c. If locators are broken, reads the Dart source to find the fix
   d. Commits updated .spec.ts files or Dart semantics fixes
   e. Opens a PR for review

4. Developer reviews the PR, merges, done.
```

**Setup required:**

1. **Playwright MCP in repo settings** — Add to the repo's Copilot coding agent MCP configuration (Settings → Copilot → Coding agent):

```json
{
  "mcpServers": {
    "playwright": {
      "type": "local",
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--headless"],
      "tools": [
        "browser_navigate",
        "browser_snapshot",
        "browser_click",
        "browser_type",
        "browser_evaluate",
        "browser_close"
      ]
    }
  }
}
```

2. **Copilot environment secrets** — In the repo's `copilot` environment, add:
   - `COPILOT_MCP_TEST_USER` → test account email
   - `COPILOT_MCP_TEST_PASSWORD` → test account password

3. **Custom agent profile** — Create `.github/agents/e2e-tester.md`:

```markdown
---
name: e2e-tester
description: Tests Pangea Chat staging flows via Playwright and fixes broken locators
---

You are an E2E testing specialist for a Flutter web app at app.staging.pangea.chat.

## Context

- The app renders to `<canvas>`. You must enable the Flutter semantics tree first by evaluating `document.querySelector('flt-semantics-placeholder')?.click()` on the page.
- After enabling semantics, wait 2 seconds for the tree to populate.
- Interactive elements are identified via ARIA roles from Flutter's semantics tree.
- Test flows are documented in `client/test/pangea/playwright-test-plan.md`.
- Deterministic test files live in `client/e2e/scripts/*.spec.ts`.
- File-to-test mapping is in `client/e2e/trigger-map.json`.

## Workflow

1. Read the assigned issue to understand which flow to test.
2. Open the staging app via Playwright MCP and walk through the flow.
3. If the flow passes, report success in the issue.
4. If a locator is broken:
   a. Read the relevant Dart source to find the widget.
   b. If the widget is missing a tooltip or Semantics label, fix the Dart file.
   c. Update the corresponding `.spec.ts` file if the locator changed.
   d. Commit both fixes.

## Credentials

Login with email `$COPILOT_MCP_TEST_USER` and password `$COPILOT_MCP_TEST_PASSWORD`.
```

4. **Setup steps** — Create or update `.github/workflows/copilot-setup-steps.yml`:

```yaml
on: workflow_dispatch
jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: lts/*
      - name: Install Playwright
        run: npx playwright install --with-deps chromium
```

**Best for:**

- Self-healing tests: agent detects broken locators and fixes them autonomously
- Post-deploy verification without human involvement
- Exploratory testing of new features described in issues
- Batch testing: assign multiple issues, agent works through them sequentially

**Trade-offs:**

- Uses Copilot premium requests + GitHub Actions minutes (included in Pro/Pro+ plans)
- Agent is non-deterministic — results may vary between runs
- Currently limited to one repo per task (our monorepo-style workspace won't be fully visible)
- The agent can only push to `copilot/*` branches, so fixes always go through PR review

### Recommended approach: layered

```
                           ┌──────────────────────────────────┐
                           │  Option D: Cloud Agent           │
                           │  Self-healing tests, exploratory │
                           │  "Fix broken E2E for settings"   │
                           └──────────┬───────────────────────┘
                                      │ creates/updates
                           ┌──────────▼───────────────────────┐
                           │  Option C: Hybrid Authoring      │
                           │  Agent writes, human reviews,    │
                           │  commits *.spec.ts files         │
                           └──────────┬───────────────────────┘
                                      │ committed specs run in
    ┌──────────────────────┐ ┌────────▼───────────────────────┐
    │  Option A: Local MCP │ │  Option B: Deterministic CI    │
    │  Developer explores, │ │  npx playwright test           │
    │  debugs interactively│ │  Fast, free, every deploy      │
    └──────────────────────┘ └────────────────────────────────┘
```

Options layer on top of each other. Start with B (deterministic CI) as the foundation, use A/C to author tests, and graduate to D for autonomous self-healing.

### Flutter-specific setup for deterministic tests

Flutter renders to `<canvas>`, so standard Playwright locators (`page.getByRole(...)`) only work after enabling the semantics tree. Every test file needs this in its setup:

```typescript
// e2e/fixtures.ts — shared across all test files
import { test as base, expect } from "@playwright/test";

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.goto(process.env.STAGING_APP_URL!);
    // Enable Flutter accessibility tree
    await page.evaluate(() => {
      const el = document.querySelector("flt-semantics-placeholder");
      if (el) (el as HTMLElement).click();
    });
    // Wait for semantics tree to populate
    await page.waitForTimeout(2000);
    await use(page);
  },
});

export { expect };
```

```typescript
// e2e/auth.setup.ts — login once, save state for all tests
import { test, expect } from "./fixtures";

const authFile = "e2e/.auth/user.json";

test("authenticate", async ({ page }) => {
  await page.getByRole("button", { name: "Login to my account" }).click();
  await page.getByRole("button", { name: "Email" }).click();
  await page
    .getByRole("textbox", { name: "Username or email" })
    .fill(process.env.TEST_USER!);
  await page
    .getByRole("textbox", { name: "Password" })
    .fill(process.env.TEST_PASSWORD!);
  await page.getByRole("button", { name: "Login" }).click();
  await expect(page).toHaveURL(/\/rooms/);
  await page.context().storageState({ path: authFile });
});
```

### Proposed file layout

```
client/
  e2e/
    fixtures.ts                   # Flutter semantics setup
    auth.setup.ts                 # Login & save auth state
    playwright.config.ts          # Config: baseURL, projects, auth
    .auth/                        # gitignored — saved login state
    scripts/
      login.spec.ts
      chat-list-navigation.spec.ts
      open-chat.spec.ts
      send-message.spec.ts
      message-toolbar.spec.ts
      course-discovery.spec.ts
      settings.spec.ts
      analytics.spec.ts
      create-dm.spec.ts
      logout.spec.ts
    trigger-map.json              # Script name → file glob triggers
```

### `trigger-map.json`

Single source of truth for diff-based test selection (used by both web CI, mobile CI, and local invocations). Each entry maps to an optional web spec and/or mobile Patrol test file:

```json
{
  "login": {
    "globs": [
      "lib/pangea/login/**",
      "lib/pages/login/**",
      "lib/config/routes.dart",
      "lib/widgets/matrix.dart"
    ],
    "web": "e2e/scripts/login.spec.ts",
    "mobile": "integration_test/patrol/login_test.dart"
  },
  "chat-list-navigation": {
    "globs": [
      "lib/pages/chat_list/**",
      "lib/pangea/chat_list/**",
      "lib/pangea/common/controllers/pangea_controller.dart",
      "lib/config/routes.dart"
    ],
    "web": "e2e/scripts/chat-list-navigation.spec.ts",
    "mobile": null
  },
  "open-chat": {
    "globs": [
      "lib/pages/chat/**",
      "lib/pages/chat_list/chat_list_item.dart",
      "lib/pangea/chat_list/**"
    ],
    "web": "e2e/scripts/open-chat.spec.ts",
    "mobile": null
  },
  "send-message": {
    "globs": [
      "lib/pages/chat/chat_input_row.dart",
      "lib/pages/chat/input_bar.dart",
      "lib/pangea/choreographer/**",
      "lib/pangea/events/**"
    ],
    "web": "e2e/scripts/send-message.spec.ts",
    "mobile": "integration_test/patrol/send_message_test.dart"
  },
  "message-toolbar": {
    "globs": [
      "lib/pangea/toolbar/**",
      "lib/pangea/text_to_speech/**",
      "lib/pangea/token_info_feedback/**",
      "lib/pangea/phonetic_transcription/**"
    ],
    "web": "e2e/scripts/message-toolbar.spec.ts",
    "mobile": null
  },
  "course-discovery": {
    "globs": ["lib/pangea/course_creation/**", "lib/pangea/course_plan/**"],
    "web": "e2e/scripts/course-discovery.spec.ts",
    "mobile": null
  },
  "settings": {
    "globs": [
      "lib/pages/settings/**",
      "lib/pangea/learning_settings/**",
      "lib/pangea/subscription/**"
    ],
    "web": "e2e/scripts/settings.spec.ts",
    "mobile": null
  },
  "analytics": {
    "globs": [
      "lib/pangea/analytics_page/**",
      "lib/pangea/analytics_practice/**",
      "lib/pangea/analytics_misc/**"
    ],
    "web": "e2e/scripts/analytics.spec.ts",
    "mobile": null
  },
  "create-dm": {
    "globs": ["lib/pages/new_private_chat/**", "lib/pangea/chat_list/**"],
    "web": "e2e/scripts/create-dm.spec.ts",
    "mobile": null
  },
  "logout": {
    "globs": [
      "lib/pages/settings/**",
      "lib/pangea/login/**",
      "lib/widgets/matrix.dart"
    ],
    "web": "e2e/scripts/logout.spec.ts",
    "mobile": null
  },
  "permissions": {
    "globs": [
      "lib/pangea/common/controllers/pangea_controller.dart",
      "lib/main.dart",
      "android/app/**",
      "ios/Runner/**"
    ],
    "web": null,
    "mobile": "integration_test/patrol/permissions_test.dart"
  }
}
```

---

## Phase 4: CI Integration

### Local invocation (developer-triggered)

A developer can run tests locally in two ways:

```sh
# Run all tests
cd client && npx playwright test --config e2e/playwright.config.ts

# Run diff-triggered tests only (against main branch)
cd client && node e2e/select-tests.js origin/main | xargs npx playwright test --config e2e/playwright.config.ts

# Run a specific script
cd client && npx playwright test e2e/scripts/send-message.spec.ts
```

Environment variables (set in shell or `.env`):

```sh
export STAGING_APP_URL=https://app.staging.pangea.chat
export TEST_USER=<your-test-email>
export TEST_PASSWORD=<your-test-password>
```

### `e2e/select-tests.js` — diff-to-test resolver

```javascript
#!/usr/bin/env node
// Usage: node e2e/select-tests.js <base-ref> [--platform web|mobile|all]
// Outputs space-separated list of test files whose triggers match the diff.

const { execSync } = require("child_process");
const { minimatch } = require("minimatch");
const triggerMap = require("./trigger-map.json");

const args = process.argv.slice(2);
const platformIdx = args.indexOf("--platform");
const platform = platformIdx !== -1 ? args[platformIdx + 1] : "web";
const baseRef =
  args.find((a) => !a.startsWith("--") && a !== platform) || "origin/main";

const diff = execSync(`git diff ${baseRef} --name-only`, { encoding: "utf-8" });
const changedFiles = diff.trim().split("\n").filter(Boolean);

const matched = new Set(["login"]); // always smoke-test login
for (const [script, entry] of Object.entries(triggerMap)) {
  if (changedFiles.some((f) => entry.globs.some((g) => minimatch(f, g)))) {
    matched.add(script);
  }
}

const testFiles = [...matched]
  .map((s) => {
    const entry = triggerMap[s];
    if (!entry) return null;
    if (platform === "mobile") return entry.mobile;
    if (platform === "web") return entry.web;
    return [entry.web, entry.mobile]; // "all"
  })
  .flat()
  .filter(Boolean);

process.stdout.write(testFiles.join(" "));
```

### GitHub Actions Workflow

```yaml
# .github/workflows/e2e-tests.yml
name: E2E Tests (Staging)

on:
  # After staging deploy completes
  workflow_run:
    workflows: ["Deploy to Staging"]
    types: [completed]
    branches: [main]

  # Manual trigger with mode selection
  workflow_dispatch:
    inputs:
      mode:
        description: "Test mode"
        required: true
        default: "diff"
        type: choice
        options:
          - smoke # login only
          - diff # diff-triggered
          - full # all scripts

  # Nightly full suite
  schedule:
    - cron: "0 6 * * *" # 6am UTC daily

env:
  STAGING_APP_URL: https://app.staging.pangea.chat
  TEST_USER: ${{ secrets.STAGING_TEST_USER }}
  TEST_PASSWORD: ${{ secrets.STAGING_TEST_PASSWORD }}

jobs:
  e2e:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    defaults:
      run:
        working-directory: client

    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0 # full history for diff

      - uses: actions/setup-node@v5
        with:
          node-version: lts/*

      - name: Install Playwright
        run: |
          npm init -y
          npm install @playwright/test minimatch
          npx playwright install --with-deps chromium

      - name: Determine test mode
        id: mode
        run: |
          if [[ "${{ github.event_name }}" == "schedule" ]]; then
            echo "mode=full" >> $GITHUB_OUTPUT
          elif [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            echo "mode=${{ inputs.mode }}" >> $GITHUB_OUTPUT
          elif [[ "${{ github.event_name }}" == "workflow_run" ]]; then
            echo "mode=diff" >> $GITHUB_OUTPUT
          fi

      - name: Select tests
        id: select
        run: |
          MODE="${{ steps.mode.outputs.mode }}"
          if [[ "$MODE" == "smoke" ]]; then
            echo "files=e2e/scripts/login.spec.ts" >> $GITHUB_OUTPUT
          elif [[ "$MODE" == "full" ]]; then
            echo "files=e2e/scripts/" >> $GITHUB_OUTPUT
          else
            FILES=$(node e2e/select-tests.js HEAD~1)
            echo "files=${FILES:-e2e/scripts/login.spec.ts}" >> $GITHUB_OUTPUT
          fi

      - name: Run Playwright tests
        run: npx playwright test --config e2e/playwright.config.ts ${{ steps.select.outputs.files }}

      - name: Upload report
        uses: actions/upload-artifact@v4
        if: ${{ !cancelled() }}
        with:
          name: playwright-report-${{ github.run_id }}
          path: client/playwright-report/
          retention-days: 14

      - name: Post results to PR
        if: ${{ github.event_name == 'workflow_run' && failure() }}
        uses: actions/github-script@v7
        with:
          script: |
            // Find the most recent PR merged to main and comment
            const { data: commits } = await github.rest.repos.listCommits({
              owner: context.repo.owner,
              repo: context.repo.repo,
              per_page: 1,
            });
            const prs = await github.rest.repos.listPullRequestsAssociatedWithCommit({
              owner: context.repo.owner,
              repo: context.repo.repo,
              commit_sha: commits[0].sha,
            });
            if (prs.data.length > 0) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: prs.data[0].number,
                body: `⚠️ **E2E tests failed** after staging deploy.\n\n[View run](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})`,
              });
            }
```

### GitHub Actions Secrets Required

| Secret                  | Description                               |
| ----------------------- | ----------------------------------------- |
| `STAGING_TEST_USER`     | Matrix username or email for test account |
| `STAGING_TEST_PASSWORD` | Password for test account                 |

### Execution Modes Summary

| Mode              | Trigger                                   | What runs                                | Cost                               |
| ----------------- | ----------------------------------------- | ---------------------------------------- | ---------------------------------- |
| **Smoke**         | Manual / post-deploy                      | `login` only                             | ~30s, free                         |
| **Diff**          | Post-deploy / manual                      | Scripts matching changed files + `login` | ~1-5min, free                      |
| **Full**          | Nightly schedule / manual                 | All 10 scripts                           | ~5-10min, free                     |
| **Agent (local)** | Developer in VS Code                      | Copilot + Playwright MCP, interactive    | LLM tokens                         |
| **Agent (cloud)** | Assign issue to `@copilot` / `e2e-tester` | Cloud agent + Playwright MCP, autonomous | Premium requests + Actions minutes |

### Future Enhancements

- Screenshot comparison for visual regression
- Performance timing assertions (page load < X seconds)
- Parallel script execution via Playwright `--workers`
- Failure auto-retry with `--retries=1`
- Post results to Slack channel
- Storage state caching to skip login between scripts
- Cloud agent auto-triggered on E2E failures: if deterministic CI fails, automatically create an issue and assign to `e2e-tester` agent to diagnose and fix

---

## Conventions

### Identifying elements

Playwright MCP sees Flutter elements via their ARIA roles. Priority for identification:

1. **Role + name**: `button "Login"`, `textbox "Password"` — most reliable
2. **Tooltip**: `IconButton(tooltip: 'Search')` → `button "Search"`
3. **Semantics label**: `Semantics(label: 'Room: Support')` → `generic "Room: Support"`
4. **Text content**: `Text('Start')` inside a button → `button "Start"`

### Adding testability

When adding new widgets, ensure:

```dart
// IconButtons — always add tooltip
IconButton(
  tooltip: 'Close dialog',  // ← required
  icon: Icon(Icons.close),
  onPressed: ...,
)

// GestureDetector / InkWell — wrap in Semantics
Semantics(
  label: 'Chat room: $roomName',
  button: true,  // if tappable
  child: GestureDetector(
    onTap: ...,
    child: ...,
  ),
)

// Images — add semanticLabel
Image.asset(
  'assets/logo.png',
  semanticLabel: 'Pangea Chat logo',  // ← or excludeFromSemantics: true if decorative
)
```

---

## Phase 5: Mobile Testing with Patrol

### Why Patrol?

Playwright covers the **web** build, but Pangea Chat also ships on **Android and iOS**. Flutter integration tests (`flutter test integration_test/`) can drive the in-app UI, but they **cannot**:

- Grant runtime permissions (camera, microphone, notifications, photos)
- Interact with native system dialogs (push notification opt-in, system alerts)
- Tap native share sheets, file pickers, or in-app-purchase dialogs
- Press the Home button, toggle Wi-Fi, or open the notification shade
- Interact with WebViews (e.g., RevenueCat checkout, OAuth flows)

[Patrol](https://patrol.leancode.co/) (by LeanCode) extends `integration_test` with **native automation** — it can do all of the above. It uses `patrolTest()` instead of `testWidgets()` and provides a `PatrolIntegrationTester` (`$`) with both Flutter finders and platform-native actions.

### Backend target (parameterizable)

Patrol tests can run against **staging** or a **local homeserver** — controlled by a `--dart-define`:

```bash
# Against staging (default for CI)
patrol test --dart-define=SYNAPSE_URL=https://matrix.staging.pangea.chat

# Against a local Synapse/Dendrite (for offline dev, uses existing test data in integration_test/synapse/)
patrol test --dart-define=SYNAPSE_URL=http://localhost:8008
```

The app reads `SYNAPSE_URL` via `Environment.synapseURL` in `lib/pangea/common/config/environment.dart`. No code change needed — the existing config mechanism handles this.

### Current state

The project already has an `integration_test/` directory with basic FluffyChat tests using `IntegrationTestWidgetsFlutterBinding`. Patrol is **not yet installed**. The existing tests will continue to work because `patrolTest()` is a superset of `testWidgets()` — migration is incremental.

### Installation

```bash
# 1. Install patrol_cli globally
flutter pub global activate patrol_cli

# 2. Add patrol as dev dependency
cd client && flutter pub add patrol --dev

# 3. Verify setup
patrol doctor
```

### pubspec.yaml additions

```yaml
dev_dependencies:
  patrol: ^4.1.1
  # integration_test already present
  integration_test:
    sdk: flutter

patrol:
  app_name: Pangea Chat
  test_directory: integration_test # reuse existing directory
  android:
    package_name: com.talktolearn.chat
  ios:
    bundle_id: com.talktolearn.chat
```

### Native side setup

**Android** (`android/app/build.gradle.kts`) — add to `defaultConfig`:

```kotlin
defaultConfig {
    // ... existing config ...
    testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
}
```

Create `android/app/src/androidTest/java/com/talktolearn/chat/MainActivityTest.java`:

```java
package com.talktolearn.chat;

import org.junit.runner.RunWith;
import pl.leancode.patrol.PatrolJUnitRunner;

@RunWith(PatrolJUnitRunner.class)
public class MainActivityTest {}
```

**iOS** — see [Patrol iOS setup](https://patrol.leancode.co/getting-started) for Xcode scheme and test target configuration.

### Test structure

Patrol tests live alongside existing integration tests:

```
client/
  integration_test/
    app_test.dart              # existing FluffyChat tests (unchanged)
    extensions/                # existing helpers
    users.dart                 # existing user credentials model
    patrol/                    # ← new Patrol-specific tests
      common.dart              # shared app startup, login helper
      login_test.dart
      send_message_test.dart
      permissions_test.dart    # native: camera, mic, notifications
      push_notification_test.dart
      share_sheet_test.dart
      subscription_test.dart   # in-app purchase flow
    synapse/                   # existing homeserver data
    dendrite/                  # existing homeserver data
```

### Shared app setup (`integration_test/patrol/common.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluffychat/main.dart' as app;

/// Launch the app and log in.
///
/// Uses the same `app.main()` pattern as the existing integration tests.
/// Patrol's own binding replaces IntegrationTestWidgetsFlutterBinding, so
/// the double-init that Patrol docs warn about does not apply here — Patrol
/// installs its binding *before* main() calls ensureInitialized(), which
/// is a no-op if a binding already exists.
///
/// Credentials via Dart compile-time env vars (same pattern as users.dart):
///   --dart-define=TEST_USER=<email>  --dart-define=TEST_PASSWORD=<password>
Future<void> launchAndLogin(PatrolIntegrationTester $) async {
  SharedPreferences.setMockInitialValues({
    'chat.fluffy.show_no_google': false,
  });
  app.main();
  await $.pumpAndSettle();

  const user = String.fromEnvironment('TEST_USER');
  const password = String.fromEnvironment('TEST_PASSWORD');

  // Text-based finders — matches existing integration test style,
  // no widget Key modifications needed.
  await $('Login to my account').tap();
  await $('Email').tap();

  // Username and password fields found by type (same as default_flows.dart)
  final inputs = find.byType(TextField);
  await $.tester.enterText(inputs.first, user);
  await $.tester.enterText(inputs.last, password);
  await $.tester.testTextInput.receiveAction(TextInputAction.done);
  await $.pumpAndSettle();
}
```

> **Finder strategy:** Text-based finders (`$('Login to my account')`) and `find.byType()` — matching the existing integration test patterns. The codebase has only ~7 static `Key` values and zero `Semantics` labels, so text/type finders require the least new code. Tooltips are localized (`L10n.of(context)...`), making `find.byTooltip()` fragile; avoid unless testing in default locale.
>
> **Backend target:** Controlled by the app's environment config. By default, the `.env` file or `environment.dart` determines which Synapse homeserver the app connects to. To target staging, pass `--dart-define=SYNAPSE_URL=https://matrix.staging.pangea.chat`. To target a local homeserver (like the existing Synapse/Dendrite test data in `integration_test/`), omit the define or point it at `localhost`.

### Example test scripts

#### `login_test.dart`

```dart
import 'package:fluffychat/pages/chat_list/chat_list_body.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'common.dart';

void main() {
  patrolTest('Login and see chat list', ($) async {
    await launchAndLogin($);
    expect(find.byType(ChatListViewBody), findsOneWidget);
  });
}
```

#### `permissions_test.dart` (native automation)

```dart
import 'dart:io';
import 'package:fluffychat/pages/chat_list/chat_list_body.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'common.dart';

void main() {
  patrolTest('Grant notification permission on first launch', ($) async {
    await launchAndLogin($);

    // When the app requests notification permission, grant it natively
    if (Platform.isIOS) {
      await $.platform.mobile.grantPermissionWhenInUse();
    }
    if (Platform.isAndroid) {
      await $.platform.mobile.grantPermissionOnlyThisTime();
    }

    // Verify app continues normally after permission grant
    expect(find.byType(ChatListViewBody), findsOneWidget);
  });

  patrolTest('App resumes correctly after backgrounding', ($) async {
    await launchAndLogin($);

    // Press home → reopen app
    await $.platform.mobile.pressHome();
    await $.platform.mobile.openApp();

    // Chat list should still be visible
    expect(find.byType(ChatListViewBody), findsOneWidget);
  });
}
```

#### `send_message_test.dart`

```dart
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'common.dart';

void main() {
  patrolTest('Send a message in a chat room', ($) async {
    await launchAndLogin($);

    // Open first chat room (by type, same approach as app_test.dart)
    await $.tester.tap(find.byType(ListTile).first);
    await $.pumpAndSettle();
    expect(find.byType(ChatView), findsOneWidget);

    // Type and send
    await $.tester.enterText(find.byType(TextField).last, 'Patrol test message');
    await $.pumpAndSettle();
    await $.tester.tap(find.byIcon(Icons.send_outlined));
    await $.pumpAndSettle();

    // Verify message appears
    expect($('Patrol test message'), findsOneWidget);
  });
}
```

### Running Patrol tests

```bash
# Run all Patrol tests on a connected device or emulator
patrol test

# Run a specific test file
patrol test -t integration_test/patrol/login_test.dart

# Run with credentials
patrol test \
  --dart-define=TEST_USER=$STAGING_TEST_USER \
  --dart-define=TEST_PASSWORD=$STAGING_TEST_PASSWORD

# Target a specific device
patrol test --device "emulator-5554"
patrol test --device "iPhone 16 Pro"
```

### Trigger map overlap

Mobile tests share trigger globs with web tests — the same Dart source change fires both runners. The canonical `trigger-map.json` (defined in Phase 2 above) uses the `{ globs, web, mobile }` format. `select-tests.js` accepts `--platform web|mobile|all` to emit the right file list for each runner.

### CI Integration for Mobile

#### Option 1: Android emulator in GitHub Actions

```yaml
# .github/workflows/e2e-mobile.yml
name: Mobile E2E Tests

on:
  workflow_run:
    workflows: ["Deploy to Staging"]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      platform:
        description: "Platform"
        required: true
        default: "android"
        type: choice
        options: [android, ios]

jobs:
  patrol-android:
    if: ${{ inputs.platform == 'android' || github.event_name == 'workflow_run' }}
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v5

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install Patrol CLI
        run: flutter pub global activate patrol_cli

      - name: Install dependencies
        working-directory: client
        run: flutter pub get

      - name: Enable KVM for Android emulator
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Start Android emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: x86_64
          profile: pixel_6
          force-avd-creation: false
          emulator-options: -no-snapshot-save -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim
          script: |
            cd client
            patrol test \
              --dart-define=TEST_USER=${{ secrets.STAGING_TEST_USER }} \
              --dart-define=TEST_PASSWORD=${{ secrets.STAGING_TEST_PASSWORD }}

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: ${{ !cancelled() }}
        with:
          name: patrol-android-results-${{ github.run_id }}
          path: client/build/app/reports/
          retention-days: 14

  patrol-ios:
    if: ${{ inputs.platform == 'ios' }}
    runs-on: macos-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install Patrol CLI
        run: flutter pub global activate patrol_cli

      - name: Install dependencies
        working-directory: client
        run: flutter pub get

      - name: Boot iOS Simulator
        run: |
          DEVICE=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed 's/.*(\(.*\)).*/\1/')
          xcrun simctl boot "$DEVICE" || true

      - name: Run Patrol tests
        working-directory: client
        run: |
          patrol test \
            --dart-define=TEST_USER=${{ secrets.STAGING_TEST_USER }} \
            --dart-define=TEST_PASSWORD=${{ secrets.STAGING_TEST_PASSWORD }}

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: ${{ !cancelled() }}
        with:
          name: patrol-ios-results-${{ github.run_id }}
          path: client/build/ios_integ/
          retention-days: 14
```

#### Option 2: Firebase Test Lab (recommended for scale)

For running tests on a farm of real devices (more reliable than emulators in CI):

```bash
# Build the Android test APKs
cd client
patrol build android --dart-define=TEST_USER=... --dart-define=TEST_PASSWORD=...

# Upload to Firebase Test Lab
gcloud firebase test android run \
  --type instrumentation \
  --app build/app/outputs/flutter-apk/app-debug.apk \
  --test build/app/outputs/flutter-apk/app-debug-androidTest.apk \
  --device model=Pixel6,version=34,locale=en,orientation=portrait \
  --timeout 10m \
  --results-dir="patrol-$(date +%s)"
```

### Mobile vs Web: coverage matrix

All web flows defined in `trigger-map.json` are planned; Phase 2 shows representative examples. ⬜ = planned but not yet written.

| Flow                             | Web (Playwright) | Mobile (Patrol) | Mobile-only? |
| -------------------------------- | :--------------: | :-------------: | :----------: |
| Login                            |        ✅        |       ✅        |              |
| Chat list navigation             |        ⬜        |       ⬜        |              |
| Open chat                        |        ✅        |       ⬜        |              |
| Send message                     |        ⬜        |       ✅        |              |
| Message toolbar (TTS, translate) |        ⬜        |       ⬜        |              |
| Course discovery                 |        ⬜        |       ⬜        |              |
| Settings                         |        ⬜        |       ⬜        |              |
| Analytics                        |        ⬜        |       ⬜        |              |
| Create DM                        |        ✅        |       ⬜        |              |
| Logout                           |        ⬜        |       ⬜        |              |
| **Permission dialogs**           |        ❌        |       ✅        |      ✅      |
| **Push notifications**           |        ❌        |       ⬜        |      ✅      |
| **Background / foreground**      |        ❌        |       ✅        |      ✅      |
| **Share sheet**                  |        ❌        |       ⬜        |      ✅      |
| **In-app purchase (native)**     |        ❌        |       ⬜        |      ✅      |

### Migration path

1. **Install Patrol** — add dev dependency, configure `pubspec.yaml` patrol section, set up native side
2. **Add `common.dart`** — shared app launch + login helper
3. **Write `login_test.dart`** — simplest flow, validates Patrol wiring
4. **Port existing `app_test.dart` flows** — migrate `testWidgets()` → `patrolTest()` incrementally (both work side-by-side)
5. **Add native-only tests** — permissions, push notifications, backgrounding
6. **CI** — start with Android emulator in GitHub Actions, graduate to Firebase Test Lab
7. **Trigger map** — update `trigger-map.json` to the richer `{ globs, web, mobile }` format

---

## NEXT STEPS (after Phase 1 merge)

### No new L10n keys were added
All P0 tooltip fixes used **existing** L10n keys:
- `settings` → "Settings" (line 1993 in `intl_en.arb`)
- `showPassword` → "Show password" (line 2017)
- `search` → "Search" (line 1826)

No localization script run is needed for this branch.

### Changes made (branch `e2e/phase1-semantics`)
| File | Change | L10n Key |
|------|--------|----------|
| `lib/pangea/login/pages/login_or_signup_view.dart` | Added `tooltip:` to settings `IconButton` | `settings` |
| `lib/pangea/login/pages/pangea_login_view.dart` | Added `tooltip:` to password toggle `IconButton` | `showPassword` |
| `lib/pangea/login/pages/signup_with_email_view.dart` | Added `tooltip:` to password toggle `IconButton` | `showPassword` |
| `lib/pangea/chat_list/widgets/pangea_chat_list_header.dart` | Added `tooltip:` to search `IconButton` | `search` |
| `.github/copilot-instructions.md` | Added Upstream Merge Rule (CRITICAL) section | — |

### Deferred to P1
- **`chat_list_item.dart` Semantics wrapper**: The `ListTile` already exposes `displayname` via its `title: Text(...)` child, making rooms findable in Playwright accessibility snapshots. A `Semantics(container: true, onTapHint: ...)` wrapper would improve screen-reader UX but requires careful nesting with `// #Pangea` markers in a deeply nested arrow-function tree. Deferred to avoid merge risk.

### Remaining Phase 1 work (P1 + P2 priorities)
- P1: Add tooltips to remaining `IconButton`s across ~50 more widgets
- P1: Add `semanticsLabel` to decorative `Icon`s in nav rail, bottom bar
- P2: Add `Semantics` wrappers to `GestureDetector` and `InkWell` widgets
- P2: Add `excludeFromSemantics: true` to decorative images

---
applyTo: "e2e/**,lib/pangea/**,lib/pages/**,lib/widgets/**,.github/workflows/e2e-*.yml,.github/skills/write-e2e-test/**"
description: "Design contracts for Playwright + axe-core testing of the Flutter web client — canvas/semantics constraints, widget testability rules, mock-mode contract, auth state, axe limits."
---

# Playwright Testing — Flutter Web Client

> For setup, commands, and troubleshooting see [`e2e/README.md`](../../e2e/README.md). For adding coverage to a new flow, use the [`write-e2e-test` skill](../skills/write-e2e-test/SKILL.md). This doc owns the **why** and the **must-hold contracts** behind those mechanics.

## Why the Flutter web app is different

The client renders to a single `<canvas>` element via CanvasKit, not DOM nodes. Standard Playwright selectors (`getByText`, `locator(css)`) cannot find anything. Playwright interacts through Flutter's **semantics tree** — an ARIA-shaped projection of the widget tree, populated from `tooltip:`, `Semantics(label:)`, and text children. Tests reach widgets via `page.getByRole(role, { name })`; pixels remain opaque.

The semantics tree is initially **disabled** for performance. Two ways to enable it: build the app with `ENABLE_SEMANTICS=true` (forces the tree on from startup — this is also what lets assistive tech and browser-driving agents operate the canvas UI by role+name instead of screenshots; off by default and opt-in only, since live semantics carries a perf cost), or click the off-screen `flt-semantics-placeholder` element at runtime. The shared fixture at [`e2e/fixtures.ts`](../../e2e/fixtures.ts) handles activation defensively — it clicks the placeholder only when the build hasn't already enabled semantics — so every spec must import `{ test, expect }` from `../fixtures`, never from `@playwright/test`, or activation is skipped and the run sees an empty tree.

## Widget testability — non-negotiable

Every widget that participates in a tested flow must surface a stable, accessible name. The rules below are **contracts on the Dart code**, not Playwright invariants — violating them breaks both automated tests and screen-reader users in the same way.

- **`IconButton` requires `tooltip:`.** No tooltip → no accessible name → unfindable.
- **`GestureDetector` / `InkWell` used as a button** must be wrapped in `Semantics(label: '...', button: true, child: ...)`. Bare gesture detectors are invisible to the accessibility tree.
- **Decorative images** declare `excludeFromSemantics: true`. **Meaningful images** declare `semanticLabel: '...'`. Default-shaped images leak as unlabelled `role=img` violations.

Pangea-specific code outside `lib/pangea/` requires `// #Pangea` / `// Pangea#` markers around any semantic-fix changes; inside `lib/pangea/`, markers are not required (the whole tree is ours).

## Bypassing paid backend calls — `mock=true`

The choreographer supports a per-request `mock` field. When set, the handler runs its full path — auth, CMS, metering, audits, retries — but every paid third-party call (OpenAI, Anthropic, embeddings, image-gen, Google TTS, Whisper / Google STT, Deepgram) is swapped for a canned, schema-shaped response. This is what makes Playwright runs economically feasible against the real backend.

Contract (full version at [`pangeachat/.github/instructions/testing.instructions.md` § Mocking paid third-party calls](https://github.com/pangeachat/.github/blob/main/.github/instructions/testing.instructions.md#mocking-paid-third-party-calls)):

- **The flag does not auto-propagate.** Add `mock=true` on the client's choreo requests when the Playwright run wants mocked responses.
- **Mock latency is a choreo environment variable, not a request field.** The default mock profile mimics real-LLM latency for load testing; the staging/test deployment zeroes it via the env knob so Playwright runs aren't needlessly slow. There is no per-request latency-override field for the client to send.
- **Mocked responses are deterministic but obviously bogus** — WA returns one double-spaced edit, image-gen returns `mock.pangea.chat/transparent-1x1.png`. Assert on shape, not content.
- **If a route triggers a 500 error code under `mock=true`, the handler likely lacks a registered mock producer.** The mock-LLM registry's `default_structured_mock(schema)` falls through to `schema()`, which fails for any schema with required fields lacking Pydantic defaults. Check `app/handlers/<h>/mock.py` in `pangeachat/2-step-choreographer`; if absent, file a bug there (`#2485` is the canonical example). The fix is a small per-handler module; do not work around it on the client side.

### Activity reads are not mockable

`mock=true` only swaps paid LLM calls inside a handler — it does not intercept an activity **read**. The version pin is server-minted on the live read/lobby path (see [`pangeachat/.github` activities doc](https://github.com/pangeachat/.github/blob/main/.github/instructions/activities.instructions.md)), so a mocked read returns no real pin and exercises nothing. Cover the pin and goal-slug contracts through one of two paths instead:

- **Mock activity *generation*** — generation is a handler, so it mocks. Its mock must emit a deterministic goals pool (the same fixed goals every run), so goal-slug derivation and star attribution are assertable against known values rather than per-run noise.
- **Seeded CMS rows** — pre-seed versioned activity rows so a real read mints a real pin. Include a seeded fixture pinned to a version past the 20-version eviction cap, so the degraded fallback path (render latest, scoring suppresses awards) has coverage and isn't only exercised in production.

## Auth state persistence

Flutter's Matrix client stores session tokens in **IndexedDB**, not cookies or localStorage. The auth-setup spec at [`e2e/auth.setup.ts`](../../e2e/auth.setup.ts) saves state with `storageState({ path, indexedDB: true })`; specs that omit `indexedDB: true` cannot restore the session, even though a default Playwright `storageState()` looks correct on paper. This is the single most common cause of "tests pass alone, fail in the suite."

Specs that want to start unauthenticated reset to `test.use({ storageState: { cookies: [], origins: [] } })`.

## Credential delivery

The shared test account is `staging_automated_tests`. Specs read `TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD` from `process.env`. Single source of truth: AWS Secrets Manager at `/staging/test-user/matrix-credentials`.

- **CI**: GitHub OIDC → `AWS_ROLE_ARN_STAGING` → `aws-actions/aws-secretsmanager-get-secrets` with `parse-json-secrets: true` populates the env vars. No GitHub-secret mirror.
- **Local**: engineers export the same env vars into `client/.env` (gitignored). See [`e2e/README.md`](../../e2e/README.md) for the SSO-fetch command.

The OIDC role's IAM grant lives in `devops/terraform/staging/iam/github-oidc/`.

## What axe can't check

The a11y suite at [`e2e/scripts/a11y.spec.ts`](../../e2e/scripts/a11y.spec.ts) runs WCAG 2.1 AA audits via `@axe-core/playwright`, scoped to `flt-semantics-host`. **Color contrast** and **visual layout** assertions are not possible — axe cannot inspect pixels inside `<canvas>`. Compensate with screenshot diffs for visual regressions; do not allowlist contrast violations to suppress them.

Axe assertions are **zero-tolerance**: `violations.toHaveLength(0)`. Fix the widget. Allowlisting is a permanent product debt, not a workaround.

## Diff-triggered CI

[`e2e/trigger-map.json`](../../e2e/trigger-map.json) maps Dart-source glob patterns to spec files. On a per-deploy run, only the specs whose triggers match the changed files run; the full suite runs nightly. Adding a new spec without wiring `trigger-map.json` means the spec never runs in pre-deploy CI — every new spec must declare its triggers.
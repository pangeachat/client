---
applyTo: "**/.github/workflows/**"
---

# CI (client)

What gates a merge to `main`, why `integrate.yaml` is shaped the way it is, and how its GitHub Actions caches behave. Measurements and the caching post-mortem that produced this shape are in pangeachat/client#6781.

## What gates a merge

`main` is protected. A PR merges when the required checks are green:

| Check | Required | Runtime | Why |
|---|---|---|---|
| `code_tests` | **yes** | ~3m33s | Format / import-sort / license / analyze / test. Installed after red `dart format` merges broke `main` (pangeachat/client#7680). |
| `accessibility_floor_check` | **yes** | ~5s | The source-level accessible-names gate [accessibility.instructions.md](accessibility.instructions.md) counts on to fail the build. Runs in parallel, so it costs nothing on the critical path. |
| `build_debug_web` | no | ~7m | Runs on every PR and is visible when red, but does not block: as the slowest PR job it would set the merge-latency floor for every PR, including doc-only ones. A break is caught by the push-to-`main` run instead. |
| `e2e_locator_check` | no | ~7s | |
| `build_debug_apk`, `build_debug_ios` | never | — | Push-only. See the reporting rule below. |

Branch protection is **non-strict** — a PR need not be rebased onto the latest `main` before merging. Strict mode would force a rebase-and-rewait cycle per merge, which is not worth it at this repo's merge rate. Repo admins can override a failing check; the override is a blanket bypass with no per-merge audit trail, so it is for unblocking, not routine use.

## Workflow shape and rationale

- **On `pull_request` / `merge_group`:** `code_tests`, `accessibility_floor_check`, `e2e_locator_check`, `build_debug_web`. Web is the active ship target and gets fast per-push feedback.
- **On push to `main`:** the above **plus** `build_debug_apk` and `build_debug_ios` (gated by `if: github.event_name == 'push'`). This catches native regressions at merge and — because the debug web build runs here too — writes the debug Rust cache to the `main` scope for PRs to restore.
- **`concurrency: cancel-in-progress`** for `pull_request` only. Superseded PR-iteration pushes cancel; `merge_group` and `main` runs finish (they gate merges / warm caches).

## Cache scoping

A cache written during a run is scoped to that run's ref: `pull_request` runs write to `refs/pull/<N>/merge` (**isolated per PR**), `push` to main writes to `refs/heads/main`. A run restores from its own ref's scope **plus the default branch**, and can never read another PR's scope.

**So the only way to share a cache across PRs is to write it on `main`.** `integrate.yaml` originally ran only on `pull_request` + `merge_group`, so the Rust cache (`target/debug`, ~425 MB) never restored on any PR and it was recompiled from source on every web/apk/ios build. Running the debug web build on push to `main` is what fixes it. The Flutter SDK and pub caches hit reliably and are left alone.

## Gotchas for future edits

- **A required check must report on every PR.** The native jobs run push-only (`if: github.event_name == 'push'`), so they must **never** be required, or PRs will wait on checks that never run. Same trap by another route: a workflow skipped by `paths` filtering leaves its check **pending**, not passing, blocking the merge forever — so never path-filter a workflow whose job is required. Gate the job with `if:` instead, which reports a *skipped* conclusion that branch protection accepts.
- **Required-check names live in branch protection, not in this repo.** Renaming a job in `integrate.yaml` without updating protection leaves PRs waiting on a context that no longer reports, and the failure reads as an infra hiccup rather than a rename. Change both together.
- **Keep the PR and main-push builds using identical debug steps.** The cache key is derived from the build; if the main-push web build diverges from the PR web build (e.g. profile vs debug, like `main_deploy.yaml`), the key stops matching and PRs miss again.

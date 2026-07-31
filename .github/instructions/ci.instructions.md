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

## Version and build number

Settings shows `Version: <semver>+<build>` as a debugging aid. The two halves come from different places.

**The semantic version** lives in `pubspec.yaml` and is bumped by hand. Pubspec's `+N` is no longer what web users see, but it still gates the release tag, so a release must still bump it. When to bump, and at which level, is part of the release process — see [deployment.instructions.md](deployment.instructions.md).

**The build number is stamped at build time, from three unrelated per-platform sources:**

| Platform | Stamped from |
|---|---|
| Web | a UTC `ddHHMM` timestamp, applied identically by both web workflows |
| Android | the Play Store internal track's highest version code, via fastlane |
| iOS | the latest TestFlight build number, via fastlane |

- **A build number only identifies a build within its own platform.** Mobile numbers come from store state, web from a clock. They are not comparable, and mobile cannot be folded into the web sequence — the stores own those counters. Capture the platform alongside the number when logging a bug report.
- **The web stamp identifies a build; it does not order one.** Dropping year and month keeps it short, at the cost of resetting on the 1st — so a later build can carry a smaller number, and web build numbers must not be compared to judge which is newer. Both web workflows share one scheme so staging and production draw from the same sequence; per-workflow run counters were tried first and drifted thousands of builds apart.

**Latent coupling.** [`app_version_util.dart`](../../lib/routes/chat_list/app_version_util.dart) also compares build numbers numerically when deciding whether to prompt an update. That path is inert: the force-upgrade gate is semantic-version-based by design, and the endpoint's build number is vestigial — see [client-version-gating.instructions.md](https://github.com/pangeachat/2-step-choreographer/blob/main/.github/instructions/client-version-gating.instructions.md). If that ever changes, the monthly reset would suppress the web update prompt; revisit the stamp format then.

## Cache scoping

A cache written during a run is scoped to that run's ref: `pull_request` runs write to `refs/pull/<N>/merge` (**isolated per PR**), `push` to main writes to `refs/heads/main`. A run restores from its own ref's scope **plus the default branch**, and can never read another PR's scope.

**So the only way to share a cache across PRs is to write it on `main`.** `integrate.yaml` originally ran only on `pull_request` + `merge_group`, so the Rust cache (`target/debug`, ~425 MB) never restored on any PR and it was recompiled from source on every web/apk/ios build. Running the debug web build on push to `main` is what fixes it. The Flutter SDK and pub caches hit reliably and are left alone.

## Gotchas for future edits

- **A required check must report on every PR.** The native jobs run push-only (`if: github.event_name == 'push'`), so they must **never** be required, or PRs will wait on checks that never run. Same trap by another route: a workflow skipped by `paths` filtering leaves its check **pending**, not passing, blocking the merge forever — so never path-filter a workflow whose job is required. Gate the job with `if:` instead, which reports a *skipped* conclusion that branch protection accepts.
- **Required-check names live in branch protection, not in this repo.** Renaming a job in `integrate.yaml` without updating protection leaves PRs waiting on a context that no longer reports, and the failure reads as an infra hiccup rather than a rename. Change both together.
- **Keep the PR and main-push builds using identical debug steps.** The cache key is derived from the build; if the main-push web build diverges from the PR web build (e.g. profile vs debug, like `main_deploy.yaml`), the key stops matching and PRs miss again.

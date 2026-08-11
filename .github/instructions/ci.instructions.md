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
- **On push to `main`:** the above **plus** `build_debug_apk` and `build_debug_ios` (gated by `if: github.event_name == 'push'`). This catches native regressions at merge, where a break is cheap to spot, without paying for a native build on every PR push.
- **`concurrency: cancel-in-progress`** for `pull_request` only. Superseded PR-iteration pushes cancel; `merge_group` and `main` runs finish (they gate merges / warm caches).

## Version, build number, and commit

Settings shows `Version: <semver>+<build>` with the build's commit SHA beneath it, as a debugging aid. The three parts answer different questions.

**The semantic version** lives in `pubspec.yaml` and is bumped by hand. Pubspec's `+N` is no longer what web users see, but it still gates the release tag, so a release must still bump it. When to bump, and at which level, is part of the release process — see [deployment.instructions.md](deployment.instructions.md).

**The build number is stamped at build time, by one of two schemes:**

| Platform | Stamped from |
|---|---|
| Web | a UTC `ddHHMM` timestamp, applied identically by both web workflows |
| Android, iOS | a UTC `YYMMDDnn` date code — `26081103` is the third build on 2026-08-10 — assigned by fastlane |

- **One date code serves both stores.** Google requires a strictly increasing integer across every upload (ceiling 2,100,000,000), and Apple requires one that increases within a version train, so a single always-rising number satisfies both at once. Fastlane takes whichever is higher: the date code, or the store's current highest build plus one. The store is the floor, which is what makes the number strictly increasing rather than merely usually increasing.
- **The web stamp identifies a build; it does not order one.** Dropping year and month keeps it short, at the cost of resetting on the 1st — so a later build can carry a smaller number, and web build numbers must not be compared to judge which is newer. That reset is also why web's scheme cannot be reused for mobile. Both web workflows share one scheme so staging and production draw from the same sequence; per-workflow run counters were tried first and drifted thousands of builds apart.
- **Web and mobile numbers are still not comparable** — one is a clock reading, the other a date code. Capture the platform alongside the number.

**The commit SHA says what code is in the build.** A build number has to be a monotonic integer, which makes it good at ordering builds and bad at identifying one — so it is not asked to. Every build workflow passes the 8-character SHA it built from into the app as a compile-time define, and Settings shows it under the version. **This is what to capture in a bug report**: the number orders builds, the SHA resolves back to code. It is empty on a locally-run build, which has no pushed commit, and Settings then shows nothing. The web deploys stamp the same SHA into `index.html`, where it serves as the Sentry release and as the cache-busting token on the asset manifests.

**Latent coupling.** [`app_version_util.dart`](../../lib/routes/chat_list/app_version_util.dart) also compares build numbers numerically when deciding whether to prompt an update. That path is inert: the force-upgrade gate is semantic-version-based by design, and the endpoint's build number is vestigial — see [client-version-gating.instructions.md](https://github.com/pangeachat/2-step-choreographer/blob/main/.github/instructions/client-version-gating.instructions.md). If that ever changes, the monthly reset would suppress the web update prompt; revisit the stamp format then.

## Cache scoping

A cache written during a run is scoped to that run's ref: `pull_request` runs write to `refs/pull/<N>/merge` (**isolated per PR**), `push` to main writes to `refs/heads/main`. A run restores from its own ref's scope **plus the default branch**, and can never read another PR's scope.

**`actions/cache` reads the default-branch scope. `moonrepo/setup-rust` does not.** That asymmetry is why the Flutter, pub, and vodozemac caches hit on every PR while the Rust one never has. Two attempts to fix the Rust side both failed: running the debug web build on push to `main` wrote a cache nothing ever read, and `cache-base: main` made the key ref-dependent so `main` and PRs could never match. Both are reverted.

**Do not spend more effort on the Rust cache.** The step it guards costs 2 seconds; the web build's real Rust cost is in `prepare-web.sh`, below. Anything that must be shared across PRs should use `actions/cache` directly.

A warm cache that is never read looks exactly like a cold one in the build log. To tell them apart, compare `lastAccessedAt` to `createdAt` on the `main`-scope entry (`gh cache list`): if they are equal, nothing has ever restored from it.

## The web build's Rust step

`scripts/prepare-web.sh` generates the vodozemac wasm bindings: it clones `dart-vodozemac` at the version pinned in `pubspec.yaml`, compiles `flutter_rust_bridge_codegen` from source, builds the wasm, moves two files into `assets/vodozemac/`, and deletes the clone. That takes **~4 minutes** and dominates every web build — for comparison, `setup-rust` costs 2 seconds.

**Cache the output, not the toolchain.** The two generated files depend only on the pinned vodozemac version and the script, so CI caches them on an exact key (`runner.os` + version + script hash) and the script skips the build when they are already present. **No `restore-keys`** — a prefix hit would restore bindings built from different inputs, which is a correctness bug rather than a slow build. `flutter_rust_bridge_codegen` is pinned for the same reason: an unpinned `cargo install` would let the output drift under a fixed key.

Two dead ends, recorded so they are not retried: repo-root `target/debug` does not exist in this repo, so caching it achieves nothing; and the vodozemac Rust build lives in `.vodozemac/rust/target`, which the script deletes before any cache-save step could see it.

## Gotchas for future edits

- **A required check must report on every PR.** The native jobs run push-only (`if: github.event_name == 'push'`), so they must **never** be required, or PRs will wait on checks that never run. Same trap by another route: a workflow skipped by `paths` filtering leaves its check **pending**, not passing, blocking the merge forever — so never path-filter a workflow whose job is required. Gate the job with `if:` instead, which reports a *skipped* conclusion that branch protection accepts.
- **Required-check names live in branch protection, not in this repo.** Renaming a job in `integrate.yaml` without updating protection leaves PRs waiting on a context that no longer reports, and the failure reads as an infra hiccup rather than a rename. Change both together.
- **Measure before optimising a CI step.** Two rounds of work went into a Rust cache guarding a 2-second step while `prepare-web.sh` burned four minutes beside it. Per-step timings are in the job log; read them before assuming where the time goes.

---
applyTo: "**/.github/workflows/**"
---

# CI Caching (client)

How the GitHub Actions caches on `integrate.yaml` behave, what was measured, and why the workflow is shaped the way it is. Baseline for the next iteration. Filed under pangeachat/client#6781.

## TL;DR

- **Flutter SDK + pub caches hit reliably.** Left alone.
- **The Rust cache (`moonrepo/setup-rust`, which caches `target/debug`) never restored on PRs** and re-tried its save every run, failing with `409 Conflict`. Root cause: GitHub Actions caches are scoped per-ref, and nothing wrote the debug-mode Rust cache to the shared `refs/heads/main` scope, so no PR could restore it.
- **Fix:** native builds (APK, iOS) and the debug web build now also run on push to `main`. The main-push web build writes the debug Rust cache to the `main` scope, which every PR restores from. APK + iOS moved off per-PR-push to cut wall-clock and runner minutes.

## GitHub Actions cache scoping (the thing that bit us)

A cache written during a run is scoped to that run's ref:

- `pull_request` runs write to `refs/pull/<N>/merge` — **isolated per PR**.
- `push` to main writes to `refs/heads/main`.

A run can **restore** from its own ref's scope **plus the default branch** (`refs/heads/main`). It cannot read another PR's scope. So the only way to share a cache across PRs is to write it on `main`.

`integrate.yaml` originally ran only on `pull_request` + `merge_group`, so it **never wrote to the `main` scope**. Confirming with `gh cache list`, nearly every entry sat under `refs/pull/<N>/merge`; the sole rust entry on `refs/heads/main` came from `main_deploy.yaml`'s **profile** web build and carried a different key hash than the **debug** builds request, so it was never a match.

Mechanics of the `409`: with no `concurrency` cancellation, several runs of the same PR overlapped. The first to finish wrote `setup-rustcargo-v1-linux-<hash>` into that PR's scope; later overlapping runs missed on restore (the winner had not saved yet) and then hit `##[warning]Failed to save: … (409) Conflict: cache entry with the same key, version, and scope already exists`. Net: `target/debug` was recompiled from source on every web/apk/ios build.

## Baseline (run 28758357756, warm Flutter cache / cold Rust cache)

Per-job wall-clock. Because the Rust cache never restored, these numbers are the cold-Rust baseline for every job that uses it.

| Job | Runner | Duration | Toolchains |
|---|---|---|---|
| `accessibility_floor_check` | ubuntu | ~5s | Python only |
| `code_tests` | ubuntu | ~3m33s | Flutter |
| `build_debug_web` | ubuntu | ~7m01s | Flutter + Rust |
| `build_debug_ios` | macos-15 | ~8m32s | Flutter + Rust |
| `build_debug_apk` | ubuntu | ~12m50s | Flutter + Java + Rust |

Wall-clock ≈ 12m50s (parallel; APK was the critical path). `build_debug_linux` is commented out, so this is 4 active build/test jobs + the a11y check, not 5.

### Cache-hit lines confirmed in logs

| Cache | Key (linux) | Status | Size |
|---|---|---|---|
| Flutter SDK | `flutter-linux-stable-3.41.4-x64-…` | `Cache hit for:` every job | 1.58 GB (2.0 GB macos) |
| Pub | `flutter-pub-linux-stable-3.41.4-x64-…` | `Cache hit for:` every job | 460 MB |
| Java / Gradle | (none) | **Not configured** — `setup-java` had no `cache:` input | — |
| Rust (`target/debug`) | `setup-rustcargo-v1-linux-<hash>` | `Cache does not exist using key …` on restore; `409 Conflict` on save | 425 MB compressed (204 MB macos) |

## Current workflow shape and rationale

- **On `pull_request` / `merge_group`:** `code_tests`, `accessibility_floor_check`, `build_debug_web`. Web is the active ship target and gets fast per-push feedback.
- **On push to `main`:** the above **plus** `build_debug_apk` and `build_debug_ios` (gated by `if: github.event_name == 'push'`). This catches native regressions at merge and — because the debug web build runs here too — writes the debug Rust cache to the `main` scope for PRs to restore.
- **`concurrency: cancel-in-progress`** for `pull_request` only. Superseded PR-iteration pushes cancel; `merge_group` and `main` runs finish (they gate merges / warm caches).
- **`setup-java` gains `cache: gradle`** so consecutive APK builds reuse `~/.gradle`.

### Gotchas for future edits

- **`main` requires the `code_tests` check** (branch protection; pangeachat/client#7680) — the format / import-sort / analyze / test gate. The native jobs (`build_debug_apk`, `build_debug_ios`) run push-only (`if: github.event_name == 'push'`), so they must **never** be added as required checks, or PRs will wait on checks that never run. `build_debug_web` and `accessibility_floor_check` do run on PRs but are intentionally left un-required.
- **Keep the PR and main-push builds using identical debug steps.** The cache key is derived from the build; if the main-push web build diverges from the PR web build (e.g. profile vs debug, like `main_deploy.yaml`), the key stops matching and PRs miss again.
- **No cache purge was needed.** The stale per-PR rust entries self-evict on GitHub's 7-day / 10 GB LRU, and the new `main`-scope debug key does not collide with the existing profile-build key.

## Still open / next iteration

- **Measure warm-Rust PR web build** after the first main-push lands the `main`-scope debug cache. Target: `build_debug_web` drops by the vodozemac/olm compile time (the delta between the ~7m cold-Rust figure above and a cache-restored run).
- `main_deploy.yaml`'s `build_web` uses `subosito/flutter-action` **without** `cache: true` — it re-downloads the SDK on every deploy. Low priority (deploys are infrequent) but an easy win.
- `actions/cache@v4` and `moonrepo/setup-rust` emit Node 20 deprecation warnings (forced to Node 24). Cosmetic until the actions update.

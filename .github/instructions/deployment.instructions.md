---
applyTo: "**/.github/workflows/**,**/deploy*"
---

# Deployment (client)

Follows the [org-wide deployment conventions](../../../.github/instructions/deployment.instructions.md) — see that doc for pipelines, environment URLs, deploy notes, and coordination. This doc covers client-specific details only.

## Branch Model

The client uses a **dual-branch model** unlike other services:

| Branch | Environment | Trigger |
|--------|------------|---------|
| `main` | Staging (`app.staging.pangea.chat`) | Merging to `main` deploys staging |
| `production` | Production (`app.pangea.chat`) | Push to `production` triggers [`release.yaml`](../../.github/workflows/release.yaml) — tags from `pubspec.yaml` version, builds Flutter web + mobile, uploads to S3 |

Production is periodically synced from `main` via merge PRs. Between syncs, the branches diverge — sometimes significantly (100+ commits).

## Deploy Mechanism

- Flutter web build → S3 upload via GitHub Actions
- Mobile builds: manual app store builds and releases
- Staging: app.staging.pangea.chat (S3 + CloudFront)
- Production: app.pangea.chat (S3 + CloudFront)

## Production Hotfix Process

When a bug must be fixed on production before the next full sync from `main`:

1. **Branch from `production`** — not `main`. The branches may have diverged enough that code from `main` doesn't compile or behaves differently on `production`.
2. **Assess cherry-pick feasibility** — If the fix already exists on `main`, try `git cherry-pick`. If `production` has diverged (e.g., a refactor changed the surrounding code), the cherry-pick may apply as a no-op or conflict. In that case, manually port the fix to be compatible with production's codebase.
3. **PR to `production`** — open a PR targeting `production`, not `main`.
4. **Bump the version** in `pubspec.yaml` — the release workflow tags from this version. If the tag already exists, the workflow fails silently. Always increment the build number (e.g., `4.1.18+6` → `4.1.18+7`).
5. **Push triggers deploy** — merging the PR (or pushing directly) to `production` triggers [`release.yaml`](../../.github/workflows/release.yaml).
6. **Forward-port to `main`** — after the hotfix is confirmed working on production, ensure the fix also exists on `main` (via the original PR, a separate PR, or the next sync merge). Otherwise the fix regresses on the next production sync.

### Key risks

- **Silent error swallowing** — if a catch block doesn't log to Sentry, production bugs become invisible. Hotfixes should always verify error observability.
- **Branch divergence** — the longer between syncs, the harder hotfixes become. Large refactors on `main` (e.g., immutable model migrations) can make cherry-picks impractical.

## Future Work

*No open issues yet.*

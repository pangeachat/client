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

## Environment Config (`.env`)

The root `.env` is the **single config source** on every platform. There is no tracked `assets/.env`; don't reintroduce one — a second copy is what previously let web silently ignore the root file.

- **Web**: `.env` is not a bundled asset. [`EnvLoader`](../../lib/pangea/common/config/env_loader.dart) fetches `/.env` from the web root at startup, so deploy jobs must place the env file at the web root (`build/web/.env`). This is what lets one web artifact be stamped with the target env at deploy time without a rebuild.
- **Native**: `.env` is a bundled asset, but the pubspec declaration stays commented on `main` because a declared-but-missing asset fails the build and `.env` is gitignored. CI writes the file and applies [`enable_mobile_env.patch`](../../scripts/enable_mobile_env.patch) to uncomment it. If the pubspec asset block changes, regenerate the patch or mobile builds break at `git apply`.
- **Env switcher** (staging builds): `envs.json` / `appConfigOverride` overlays whatever dotenv loaded; it is independent of where the file came from.

The GitHub Actions environment variable `WEB_APP_ENV` is the source for generated `.env` files in deploy workflows. It should include the runtime web Firebase analytics config as `GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64`, with a base64-encoded Firebase options JSON value for the target environment.

## CI Secrets

Mobile Firebase messaging setup uses GitHub Actions secrets:

| Secret | Destination |
|--------|-------------|
| `GOOGLE_SERVICES_JSON` | `android/app/google-services.json` |
| `GOOGLE_SERVICES_PLIST` | `ios/Runner/GoogleService-Info.plist` |

Both values are base64-encoded file contents. Run [`configure-firebase-messaging.sh`](../../scripts/configure-firebase-messaging.sh) to set up the environment.

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

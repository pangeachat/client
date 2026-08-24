---
applyTo: "**/.github/workflows/**,**/deploy*"
---

# Deployment (client)

Follows the [org-wide deployment conventions](../../../.github/.github/instructions/deployment.instructions.md) — see that doc for pipelines, environment URLs, deploy notes, and coordination. This doc covers client-specific details only.

## Branch Model

The client uses a **dual-branch model** unlike other services — but the production *deploy trigger* is the same as everywhere else: **publishing a GitHub release**.

| Branch | Environment | Trigger |
|--------|------------|---------|
| `main` | Staging (`app.staging.pangea.chat`) | Merging to `main` deploys staging |
| `production` | Production (`app.pangea.chat`) | **Nothing deploys on push.** The branch records the commit a release is cut from; publishing a GitHub release targeting it runs [`release.yaml`](../../.github/workflows/release.yaml) — builds Flutter web, uploads to S3, invalidates CloudFront, posts to Matrix |

Separating the two is the point: merging into `production` marks where we are cutting from and is safe to do whenever, and the release publish is the single deliberate act that ships to users. Cut the release against the branch — `gh release create <tag> --target production` — because a `release` event runs the workflow file **from the tagged commit**, so the copy of `release.yaml` on `production` is the one that runs. A production redeploy with no new release is `workflow_dispatch` on the same workflow.

Production is periodically synced from `main` via merge PRs. Between syncs, the branches diverge — sometimes significantly (100+ commits).

## Deploy Mechanism

- Flutter web build → S3 upload via GitHub Actions
- Mobile builds: both platforms follow the same shape — every build, staging or production, is a button (manual `workflow_dispatch` with the environment selected), and promotion to end users stays a human step in the store console. Store builds are **not** wired into `release.yaml`; a web release does not produce a mobile build. Android: [`android-playstore.yml`](../../.github/workflows/android-playstore.yml) uploads a signed appbundle to the Play Store internal track. iOS: [`ios-testflight.yml`](../../.github/workflows/ios-testflight.yml) uploads a signed IPA to TestFlight (fastlane match signing; certs live encrypted in the private `pangeachat/ios-certificates` repo). CI is the only sanctioned path for store builds because the checked-in Firebase config files are the staging ones — only env-secret-driven CI builds are guaranteed to carry the right Firebase project (FCM tokens are project-scoped; a mismatch kills push).
- Staging: app.staging.pangea.chat (S3 + CloudFront)
- Production: app.pangea.chat (S3 + CloudFront)

## Versioning

The semantic version in `pubspec.yaml` is bumped by hand. (The build number after the `+` is stamped automatically per platform at build time — see [ci.instructions.md](ci.instructions.md).)

**Which level to bump.** The wall itself is mechanical: the force-upgrade floor walls out any client strictly below it, at **any** level — patch included. The levels are policy, defined by what we plan to do to the fleet. Raising the floor is a separate, deliberate release step — see [client-version-gating.instructions.md](https://github.com/pangeachat/2-step-choreographer/blob/main/.github/instructions/client-version-gating.instructions.md).

- **Major** — a release you intend to eventually force the whole fleet onto: a protocol or stored-data break, or a cutover that ends coexistence with the previous line.
- **Minor** — a release you may later want to force: a notable feature, or a migration users must land on before old clients become a liability.
- **Patch** — the default, and right for most work including most feature work. Not used for planned fleet retirement; a patch-level floor raise is the emergency lever (e.g. forcing a security fix onto the fleet).

Choosing a level is answering one question: *would we ever force someone onto this?* If no, it is a patch. A yes driven by a breaking change is also the deploy-note trigger: that change needs a `deploy-note` issue (org [deployment § Deploy Notes](https://github.com/pangeachat/.github/blob/main/.github/instructions/deployment.instructions.md#deploy-notes)), and the eventual fleet retirement is the floor-flip deploy note.

These definitions are analogous to the SemVer standard definitions for these version numbers, except defined in terms of the need for user-side forced updates instead of in terms of backwards compatibility.

**Bumping is a judgment call, not a per-PR obligation** — most PRs need none. Raise it when a PR is the thing a future floor-raise would target, or when a release is being cut. A release must still bump `+N`, so the tag is unique and the version the app reports matches the release it came from — but a reused version now fails loudly at `gh release create` instead of silently producing no tag and no deploy, because the workflow no longer creates the tag itself.

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
4. **Bump the version** in `pubspec.yaml` — see [Versioning](#versioning). A hotfix is a patch: increment the build number (e.g., `4.1.18+6` → `4.1.18+7`).
5. **Publish a release to deploy** — merging the PR to `production` deploys nothing. Cut the release once the fix is on the branch: `gh release create <version> --target production` (see [release-process](https://github.com/pangeachat/.github/blob/main/.github/instructions/release-process.instructions.md) for the body contract). Publishing runs [`release.yaml`](../../.github/workflows/release.yaml).
6. **Forward-port to `main`** — after the hotfix is confirmed working on production, ensure the fix also exists on `main` (via the original PR, a separate PR, or the next sync merge). Otherwise the fix regresses on the next production sync.

### Key risks

- **Silent error swallowing** — if a catch block doesn't log to Sentry, production bugs become invisible. Hotfixes should always verify error observability.
- **Branch divergence** — the longer between syncs, the harder hotfixes become. Large refactors on `main` (e.g., immutable model migrations) can make cherry-picks impractical.

## Future Work

*No open issues yet.*

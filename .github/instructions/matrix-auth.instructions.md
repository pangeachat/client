---
applyTo: "**/.env*"
---

# Matrix Auth — Staging Test Tokens

How to obtain a Matrix access token for staging API testing (choreo endpoints, Synapse admin API, Playwright login, etc.).

## Credentials

The shared staging test account is `staging_automated_tests`. Credentials live in `client/.env` (gitignored):

- `TEST_MATRIX_USERNAME` — Matrix username (localpart, no `@` or domain)
- `TEST_MATRIX_PASSWORD` — password

Read these values from the file at runtime. **Never hardcode credentials in skills, scripts, or chat output.** If `client/.env` is missing them, see [`e2e/README.md` § Credentials](../../e2e/README.md#credentials) for the AWS Secrets Manager / mirrored-env fetch.

## Environment profiles — `.env` is generated, not edited

`client/.env` is a copy of a per-environment profile (`.env.local`, `.env.staging` — gitignored), switched by [`scripts/use-env.sh`](../../scripts/use-env.sh); never edit `.env` in place. Each profile carries the routing keys **and the `TEST_MATRIX_*` credentials that exist on that profile's homeserver** (`.env.local` → the local `@learner` account, `.env.staging` → `staging_automated_tests`). The pairing is the point: `?devlogin=1` and the endpoint test suites follow `.env`, so a homeserver pointed one way with credentials from the other guarantees login 403s and hung dev-login boots. Sessions that used to sed individual keys in `.env` drifted exactly into that state — switch profiles whole, via the script.

## Bypass the login UI in debug (`?devlogin=1`)

The web client renders its login form on a canvas, so a password manager can't fill it and browser-driving agents struggle to type into it — reaching a logged-in state is the slowest part of local QA. A debug-only shortcut signs the local build straight into the test account.

Append `?devlogin=1` to the URL: `http://localhost:8090/?devlogin=1` (or inside a hash route, `http://localhost:8090/#/world?devlogin=1`).

- **Intentional, per load.** A normal load (`http://localhost:8090/`) shows the real login flow untouched, so that flow stays testable in debug. The bypass fires only when the param is present.
- **Uses `TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD` from `.env`** via the SDK's own password login, so the session is always valid (no stale-token problem a saved Playwright `storageState` has).
- **Never touches production.** Gated to debug builds (release builds — staging/prod — ignore it) and authenticates only against a localhost or staging host (the host `SYNAPSE_URL` points to — the same one the login actually connects to).
- On a staging-pointed build it signs into the shared `staging_automated_tests` account; log out / prune the `dev-login` device when done so stray sessions don't accumulate.
- No-op if a client is already logged in (log out first to switch accounts).

Implementation: `lib/pangea/common/config/dev_login.dart`, invoked from `MatrixState.initState`.

## Get a Matrix Access Token

```sh
curl -s -X POST 'https://matrix.staging.pangea.chat/_matrix/client/v3/login' \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": "<USERNAME_WITHOUT_@_OR_DOMAIN>"},
    "password": "<TEST_MATRIX_PASSWORD>"
  }' | python3 -m json.tool
```

The response contains `access_token`, `user_id`, `device_id`, and `home_server`.

### Extracting the token programmatically

```sh
# Read creds from client/.env
TEST_USER=$(grep TEST_MATRIX_USERNAME client/.env | sed 's/.*= *"//;s/".*//')
TEST_PASS=$(grep TEST_MATRIX_PASSWORD client/.env | sed 's/.*= *"//;s/".*//')

# Login and extract token
MATRIX_TOKEN=$(curl -s -X POST 'https://matrix.staging.pangea.chat/_matrix/client/v3/login' \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$TEST_USER\"},\"password\":\"$TEST_PASS\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "$MATRIX_TOKEN"
```

## Use the Token

### Choreo API

Choreo gates on the Matrix token alone — it validates the bearer via Synapse `whoami` plus the RevenueCat entitlement check, and reads no API-key header:

```sh
curl -s 'https://api.staging.pangea.chat/choreo/<endpoint>' \
  -H "Authorization: Bearer $MATRIX_TOKEN"
```

### Synapse Client-Server API

```sh
curl -s 'https://matrix.staging.pangea.chat/_matrix/client/v3/joined_rooms' \
  -H "Authorization: Bearer $MATRIX_TOKEN"
```

### Synapse Admin API

The test account is **not** a server admin. For admin endpoints, use the bot account or a real admin token. See [synapse-docs.instructions.md](../../../.github/.github/instructions/synapse-docs.instructions.md) for the full Admin API reference.

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `M_FORBIDDEN` | Token expired or invalidated | Re-run the login curl to get a fresh token |
| `M_UNKNOWN_TOKEN` | Token from a different homeserver or old session | Confirm you're hitting `matrix.staging.pangea.chat` |
| `Could not validate Matrix token` from choreo | Choreo's homeserver rejected the bearer — wrong environment's token, or expired | Confirm the token's homeserver matches the choreo you're calling, then re-run the login curl |
| `M_USER_DEACTIVATED` | Test account was deactivated | Re-register or use a different test account |

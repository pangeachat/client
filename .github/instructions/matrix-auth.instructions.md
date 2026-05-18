---
applyTo: "**/.env,**/assets/.env*"
---

# Matrix Auth — Staging Test Tokens

How to obtain a Matrix access token for staging API testing (choreo endpoints, Synapse admin API, Playwright login, etc.).

## Credentials

The shared staging test account is `staging_automated_tests` on
`staging.pangea.chat`. Authoritative source is AWS Secrets Manager at
`/staging/test-user/matrix-credentials` (JSON with `TEST_MATRIX_USERNAME`
and `TEST_MATRIX_PASSWORD` keys). CI fetches it via OIDC; for local use,
either pull it down with the AWS CLI or read the mirrored values from
`2-step-choreographer/.env`.

```sh
# Local fetch from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id /staging/test-user/matrix-credentials \
  --query SecretString --output text | python3 -m json.tool
```

Expected variable names:

- `TEST_MATRIX_USERNAME` — localpart (e.g. `staging_automated_tests`)
- `TEST_MATRIX_PASSWORD` — password

**Never hardcode credentials in skills, scripts, or chat output.**

## Get a Matrix Access Token

```sh
curl -s -X POST 'https://matrix.staging.pangea.chat/_matrix/client/v3/login' \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": "<TEST_MATRIX_USERNAME>"},
    "password": "<TEST_MATRIX_PASSWORD>"
  }' | python3 -m json.tool
```

The response contains `access_token`, `user_id`, `device_id`, and `home_server`.

### Extracting the token programmatically

```sh
# Read creds from 2-step-choreographer/.env
TEST_USER=$(grep ^TEST_MATRIX_USERNAME 2-step-choreographer/.env | sed 's/.*= *"\?//;s/"\?$//')
TEST_PASS=$(grep ^TEST_MATRIX_PASSWORD 2-step-choreographer/.env | sed 's/.*= *"\?//;s/"\?$//')

# Login and extract token
MATRIX_TOKEN=$(curl -s -X POST 'https://matrix.staging.pangea.chat/_matrix/client/v3/login' \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$TEST_USER\"},\"password\":\"$TEST_PASS\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "$MATRIX_TOKEN"
```

## Use the Token

### Choreo API

Choreo requires **both** the Matrix token and the API key (from `CHOREO_API_KEY` in `client/assets/.env`):

```sh
curl -s 'https://api.staging.pangea.chat/choreo/<endpoint>' \
  -H "Authorization: Bearer $MATRIX_TOKEN" \
  -H 'api-key: <CHOREO_API_KEY>'
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
| `Could not validate Matrix token` from choreo | Missing `api-key` header | Add both `Authorization` and `api-key` headers |
| `M_USER_DEACTIVATED` | Test account was deactivated | Re-register or use a different test account |

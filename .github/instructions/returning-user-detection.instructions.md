---
applyTo: "lib/pangea/login/**,lib/pangea/authentication/**,lib/pages/login/**"
---

# Returning User Detection — Preventing Duplicate Accounts

Users frequently create multiple accounts because they forget whether they signed up with Google, Apple, or email. This doc defines the strategy for remembering and surfacing the previous login method.

See also: [modules.instructions.md](modules.instructions.md) | [matrix-auth.instructions.md](matrix-auth.instructions.md)

## Problem

Three sign-in methods (Google SSO, Apple SSO, email/password) each create a **separate Matrix account** with a different localpart. Synapse blocks duplicate emails via `already_in_use.html`, but that page doesn't tell the user *which* method they used before. There is no client-side hint either.

## Strategy — Three Layers

### Layer 1: Keychain-Backed Login Method Hint (Phase 1)

**Goal**: On the login/signup screen, show "You previously signed in with {method}" and visually emphasize that button.

| Decision | Choice | Why |
|---|---|---|
| **Storage** | `flutter_secure_storage` (iOS Keychain / Android Keychain) | Survives app uninstall on iOS. Already a dependency (v9.2.4, used by [`init_with_restore.dart`](../../lib/utils/init_with_restore.dart)). Android Keychain persistence across uninstall depends on `allowBackup` / Google backup — less reliable than iOS, but still better than nothing. |
| **What to store** | `last_login_method` enum value (`google`, `apple`, `email`) and `last_login_user_id` (Matrix user ID) | Method alone is sufficient for the hint. User ID helps disambiguate if multiple people share a device. |
| **When to write** | Immediately after a successful `client.login()` call — both SSO and email/password paths | Single write point in both [`p_sso_button.dart`](../../lib/pangea/login/widgets/p_sso_button.dart) (SSO) and [`p_login.dart`](../../lib/pangea/authentication/p_login.dart) (email) |
| **When to read** | On mount of [`SignupPageView`](../../lib/pangea/login/pages/signup_view.dart) and [`LoginOptionsView`](../../lib/pangea/login/pages/login_options_view.dart) | Read once, cache in controller state |
| **UX when hint exists** | Show a banner or subtitle: "Welcome back! You previously signed in with Google." Visually emphasize the matching SSO button (e.g., outlined/highlighted). Other buttons remain available but de-emphasized. | Don't hide other methods — the user may intentionally want a different one. |
| **UX when no hint** | Show all three options equally (current behavior) | First-time users or users who cleared Keychain |
| **Logout behavior** | Do NOT clear the stored hint on logout | The whole point is to remember the method after logout/uninstall |
| **Multi-user devices** | Store only the most recent login. If a different user logs in, overwrite. | Simplest approach. Multi-user hint tracking adds complexity for a rare case. |

**Key for `flutter_secure_storage`**: `pangea.last_login_method` and `pangea.last_login_user_id`. Use the `pangea.` prefix to namespace away from the existing `session_backup` keys.

### Layer 2: Sign in with Apple Auto-Detection (Phase 1)

Apple's `ASAuthorizationController` (via `sign_in_with_apple` Flutter package) can detect whether the user's Apple ID has previously been used with the app — server-side on Apple's end, not local storage. This works even on a fresh device the user has never used before.

| Decision | Choice | Why |
|---|---|---|
| **Current implementation** | Web-based OIDC redirect via `FlutterWebAuth2` | Works on all platforms, simple |
| **Proposed change** | Use the `sign_in_with_apple` package for native iOS flow, keep web redirect as fallback for Android/web | Native flow triggers Apple's "Continue with Apple" auto-suggestion sheet when it detects prior usage. Also provides a faster, more polished UX on iOS. |
| **Scope** | iOS only — Apple Sign In on Android/web stays as web redirect | Apple's auto-detection only works via the native iOS SDK |
| **Migration concern** | Low — the OIDC provider ID stays `oidc-apple` on Synapse's side regardless of whether the client uses native or web flow. The login token exchange is the same. |

### Layer 3: Server-Side Device-to-Account Mapping (Phase 2)

Associate a stable device identifier with the Matrix user ID on the server. When the app opens, send the device ID to a lookup endpoint to check if this device has logged in before.

| Decision | Choice | Why |
|---|---|---|
| **Device ID source** | Matrix `device_id` from the login response + platform-specific ID (iOS `identifierForVendor`, Android `Settings.Secure.ANDROID_ID`) | Matrix device ID changes per login session. Platform IDs are more stable but have privacy restrictions. |
| **Server endpoint** | New endpoint on 2-step-choreographer or a Synapse module | Needs to store `{device_fingerprint → user_id, login_method}` mapping |
| **Privacy** | Device fingerprints are PII — must be hashed before storage, documented in privacy policy, and subject to GDPR deletion | Non-trivial compliance work |
| **When this adds value** | Covers the case where the user switches to a new device AND has cleared Apple Keychain (rare). Also covers Android where Keychain persistence is less reliable. |

**Recommendation**: Defer to Phase 2. Layers 1 + 2 cover the vast majority of cases. Only build Layer 3 if duplicate account reports persist after Phase 1.

## Improved Error Page (Phase 1, Server-Side)

Update [`already_in_use.html`](../../../synapse-templates/templates/already_in_use.html) to tell the user **which login method** is associated with their email. Requires a Synapse module or template variable that looks up the email's `external_ids` to determine the OIDC provider.

## Future Work: Account Linking via MAS

The Matrix Authentication Service (MAS) natively supports linking multiple auth methods (Google + Apple + email) to a single Matrix account. This eliminates the duplicate account problem entirely rather than just mitigating it.

MAS is a separate Rust service that replaces Synapse's built-in auth. The ansible playbook already has roles for it (`matrix_authentication_service_*`), but they are not configured.

**What MAS provides:**
- Automatic account linking by verified email — user signs up with Google, later tries Apple with the same email, MAS links Apple to the existing account
- User-facing settings page to add/remove login methods
- Password + SSO on the same account
- Migration tool (`syn2mas`) for existing Synapse users

**What MAS costs:**
- New service to deploy and maintain (Rust binary + PostgreSQL)
- One-way migration with maintenance window (`syn2mas`)
- Client login flow changes from Synapse SSO redirect to OIDC Authorization Code + PKCE against MAS (matrix-dart-sdk supports this)
- Full retest of all auth paths across iOS, Android, web

**When to consider**: If duplicate accounts remain a significant support burden after Phase 1, or if Element's ecosystem moves further toward requiring MAS. Not justified at current scale (~79 MAU).

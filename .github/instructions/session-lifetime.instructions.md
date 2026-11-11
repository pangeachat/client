---
applyTo: "lib/utils/client_manager.dart,lib/utils/init_with_restore.dart,lib/features/authentication/change_password_extension.dart,lib/features/authentication/token_renewal_extension.dart,lib/features/authentication/module_token_renewal_client.dart"
description: "How a learner's session lasts: day-long access tokens renewed in the background, renewal before every request, the one condition that signs a learner out, and keeping the session through a password change."
---

# Staying Signed In — Session Lifetime and Renewal

## Goal

A learner who signs in stays signed in until one of these happens: they sign out themselves, the session is ended for them, or the server rejects it. Poor connectivity never signs a learner out. Opening the app, or bringing it back from the background, after several days away works the same as after a few minutes.

## How a session lasts

The homeserver issues access tokens that expire after 24 hours (`refreshable_access_token_lifetime`, security#51), together with a refresh token. The app trades the refresh token for a new access token before the old one runs out, and the learner never sees it happen. A learner who opens the app less than once a day, or leaves it in the background or in an open browser tab for a day, comes back to an expired access token, so renewal is part of the normal path, not an edge case.

## Renew before every request

Before the app sends a request that needs the access token, it renews the token if it has expired or is about to. That covers the Pangea services, profile writes and the homeserver's Pangea module calls, at startup and after it, including the first requests after the app comes back from the background or a browser tab wakes up. A request sent with a token the app already knows has expired fails, and the surface that asked for it stays empty or shows an error: the world map without pins, or a course page that does not load ([#9835](https://github.com/pangeachat/client/issues/9835)). Requests that arrive together wait for one shared renewal. If renewal hasn't finished after 10 seconds, for example because the device is offline, the request goes out with the token it has, and renewal is retried when the server is reachable. At startup the app also waits for the renewal before it goes on, so the homeserver's own first requests carry the new token too.

CMS images, the live speech-to-text connection, and the background analytics and dosage uploads take the token before their request goes out, when the screen is drawn or the event is recorded, so they are not renewed first.

## Sign out only when the server says so

The app signs a learner out only when the homeserver rejects the session: the refresh token is invalid or revoked, or the account is deactivated. A renewal that fails because the device is offline, the homeserver is unreachable or the request times out keeps the session, and the app tries again when it next reaches the server. The Matrix SDK signs out on any failed renewal, so our fork of it (`pangeachat/matrix-dart-sdk`) is where this rule is enforced.

## Changing the password

Changing the password signs the learner out of every other device but keeps them signed in on the one they changed it from. The homeserver also ends the current session when the password changes, so the app signs in again on the same device with the new password straight away. The learner stays signed in, and the device keeps its identity and encryption keys. If that sign-in fails, the app still tells the learner their password changed, because it did, and the team is alerted; the learner is then signed out on this device within a day.

See also: [signup-and-login.instructions.md](signup-and-login.instructions.md) for the signed-out screens, and [returning-user-detection.instructions.md](returning-user-detection.instructions.md) for what happens when a learner comes back signed out.

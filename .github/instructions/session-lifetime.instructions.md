---
applyTo: "lib/utils/client_manager.dart,lib/utils/init_with_restore.dart"
description: "How a learner's session lasts: day-long access tokens renewed in the background, renewal before the app's first requests, and the one condition that signs a learner out."
---

# Staying Signed In — Session Lifetime and Renewal

## Goal

A learner who signs in stays signed in until one of these happens: they sign out themselves, the session is ended for them, or the server rejects it. Poor connectivity never signs a learner out. Opening the app after several days away works the same as opening it after a few minutes.

## How a session lasts

The homeserver issues access tokens that expire after 24 hours (`refreshable_access_token_lifetime`, security#51), together with a refresh token. The app trades the refresh token for a new access token before the old one runs out, and the learner never sees it happen. A learner who opens the app less than once a day starts almost every visit with an expired access token, so renewal is part of the normal startup path, not an edge case.

## Renew before the first requests

When the app starts, it renews an expired or expiring access token before it sends any request that needs one. That covers the Pangea services, profile writes and the homeserver's Pangea module calls. A request sent with a token the app already knows has expired fails, and the surface that asked for it stays empty or shows an error. In September 2026 that left the world map without pins and course pages on an error. If renewal hasn't finished after 10 seconds, for example because the device is offline, the app carries on starting and renewal is retried when the server is reachable.

## Sign out only when the server says so

The app signs a learner out only when the homeserver rejects the session: the refresh token is invalid or revoked, or the account is deactivated. A renewal that fails because the device is offline, the homeserver is unreachable or the request times out keeps the session, and the app tries again when it next reaches the server. The Matrix SDK signs out on any failed renewal, so our fork of it (`pangeachat/matrix-dart-sdk`) is where this rule is enforced.

See also: [signup-and-login.instructions.md](signup-and-login.instructions.md) for the signed-out screens, and [returning-user-detection.instructions.md](returning-user-detection.instructions.md) for what happens when a learner comes back signed out.

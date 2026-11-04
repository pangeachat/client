---
applyTo: "lib/features/connection_status/**"
description: "How the app tells the user it cannot reach Pangea (their device is offline, Pangea is down, or the network blocks Pangea), what it tells them to do, and how the team hears about it."
---

# Connection status

When the app cannot reach Pangea, it tells the user which of three causes it is, because each has its own fix: an offline device reconnects or waits; while Pangea is down, the user waits for us; on a network that blocks Pangea, such as a school's Wi-Fi filter, the user switches network or asks IT. It also reports what we can act on to Sentry, and lets a user on a filtered network ask us for help.

## What the user sees

The connection banner and the filtered-network banner share one slot at the top of the app. The filtered-network banner wins, because the user can act on it. Either can be dismissed, since an offline user may still need the page beneath, and comes back when its news changes. It is the one connection indicator on every layout; the chat header shows no sync status.

**Practice while you wait.** While either banner says Pangea is out of reach, it offers vocab practice, which runs offline ([practice-exercises](practice-exercises.instructions.md#offline-practice)), to a signed-in learner the app does not know to be unsubscribed, with a full session's worth of words whose meanings are saved on the device, unless practice is in progress or open. In the single-column layout ([routing](routing.instructions.md)) both banners are one compact row, with the offer as an unlabeled practice icon beside the close button, so either clears the handle of a sheet risen to just below the top bar, and the sheet does not move.

When the chat server or the Pangea API is blocked, the filtered-network banner says this network is blocking Pangea Chat. Its button opens the guidance: on a phone (the iOS and Android apps, and phone browsers), turn off Wi-Fi and use mobile data; on any other device, use a phone's hotspot. A section for everyone, so the app need not know who is a teacher, gives IT staff the domains to allowlist, with a copy button. When only a feature's host is blocked, that feature shows a short note that opens the same guidance, and the rest of the screen works.

## Hosts the app needs

A blocked chat server or Pangea API stops the app. A blocked host for images, video, the map, or Google or Apple sign-in ([signup-and-login](signup-and-login.instructions.md)) breaks only that feature; email sign-in still works.

## Telling the causes apart

The check runs only when something has gone wrong, so a healthy network never pays for it. It asks the host that failed, then a neutral address that phones and computers ask to learn whether they are online, which filters let through:

- Neither answers: the device is offline.
- Only the neutral address answers, and the host refused the connection or another site answered for it: the network is filtered.
- The host answered slowly or with our own server's error: an outage or a slow network, never a block.

A deploy makes the chat server and the Pangea API refuse connections for a minute or more, as a filter does. So a refusal from either counts as a block only after three minutes, and its guidance and Sentry report wait that long.

A user who switches to mobile data carries on without restarting: a block clears once a request to its host succeeds, and a network change runs the check again. The map is the exception: the browser can show a saved tile on a network that blocks the map, so a tile that loads starts a check instead.

## Losing the connection

When the connection to the chat server is lost, the banner says the device is offline or, if the device is online, that the app can't reach Pangea Chat; when the connection returns, "Back online" for a few seconds.

**Before sign-in.** The banner shows on the sign-in and sign-up pages too. A failed sign-in that cannot reach the chat server says so at once, so nobody waits three minutes to learn that something is wrong; the form still shows its own error.

## Sentry

Each filtered verdict reports one Sentry error per host category per session, tagged with the user's courses, so one class's reports gather under its course, which leads to its teacher. It adds no personal data beyond what every client event carries (the account ID and, on the web, the IP address), and not the network's name.

A lost connection on an online device reports one Sentry warning per session. An offline device reports nothing, because there is nothing for us to fix.

## Asking Pangea for help

The guidance ends with the user's email, filled in from the account when the app has one, and an **Ask Pangea for help** button. The request reaches support@pangea.chat as a CMS form submission ([form-submissions](../../../cms/.github/instructions/form-submissions.instructions.md#network-help-requests) lists what it carries).

The team is emailed about a block only when someone asks, which keeps the volume low: a class behind one filter usually sends one request, from its teacher. Each account sends at most one a day. Signing out lifts the limit for the next account on a shared device; a request still waiting goes out as the earlier account's.

When the CMS is blocked too, the request waits on the device for the next good connection, usually mobile data or a hotspot, and the user sees it waiting, then sent. If the CMS refuses it, the guidance asks the user to email support@pangea.chat, and the app tries again only next session.

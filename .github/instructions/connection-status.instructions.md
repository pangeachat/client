---
applyTo: "lib/features/connection_status/**"
description: "How the app tells the user it cannot reach a server it needs, what it tells them to do, and how the team hears about it."
---

# Connection status

When the app cannot reach a server it needs, it tells the user the cause, and what to do: if the device is offline, the user reconnects or waits; if our servers are down, the user waits for us; if the network blocks a server, as a school's Wi-Fi filter can, the user switches network or asks IT. It also reports the problems we can fix to Sentry, and lets a user on a blocked network ask us for help.

## Servers the app needs

Without each server, this stops working:

- Chat server: everything, from sign-in to chat and courses.
- Pangea API, which includes the CMS: the language tools, activities and subscriptions.
- Image server: activity and course images.
- YouTube: activity videos.
- Map server: the world map.
- SSO sign-in ([signup-and-login](signup-and-login.instructions.md)): signing in that way; email sign-in still works.

## Telling the causes apart

The device is offline when the phone, computer or browser says it has no network, or when a request to a neutral address fails too. When messages stop arriving from the chat server, but the neutral address works, the app treats the chat server as down.

A server is blocked when it refuses the connection, or another site answers in its place, while the neutral address works. A server that answers at all, even with an error, or is only slow, is not blocked. Our own servers, the chat server and the Pangea API, refuse connections for a minute or more while we update them, so a refusal from either counts as a block only after three minutes.

On the web, the app cannot see a filter's block page, so it misses filters that show one instead of refusing the connection.

**Before sign-in.** With no messages to watch, the banner relies on the device's network status and on failed sign-ins. It says at once when a sign-in cannot reach the chat server, so nobody waits three minutes to learn that something is wrong.

## What the user sees

Two banners share the top of every page, and only one shows at a time:

- The connection banner says the device is offline or the app can't reach Pangea Chat, then "Back online" when the connection returns. It follows only the chat server and the device's network status.
- The filtered-network banner says this network is blocking Pangea Chat. It shows when the network blocks the chat server or the Pangea API, and wins over the connection banner, because the user can act on it.

Both offer offline vocab practice to users who qualify ([practice-exercises](practice-exercises.instructions.md#offline-practice)). Either can be dismissed, and comes back when its news changes.

When the image server, YouTube or the map is blocked, a note takes that feature's place and the rest of the screen works. On the web, a blocked Google or Apple sign-in offers email sign-up instead ([signup-and-login](signup-and-login.instructions.md)). An outage of any server but the chat server shows only the feature's own error.

The filtered-network banner's button and each note open the same guidance: on a phone, in the app or its browser, switch from Wi-Fi to mobile data; on any other device, use a phone's hotspot. It also lists the domains for IT staff to allow, shown to everyone so the app need not know who is a teacher.

## Repair

### Reconnecting

When the connection to the chat server returns, the connection banner says "Back online" for a few seconds. A block clears once a request to its server succeeds, and a network change runs the check again, so a user who switches to mobile data carries on without restarting. The map is the exception: a tile that loads may come from the browser's saved copy, so it starts a check instead.

### Reporting to the team

**Asking Pangea for help.** The guidance ends with an **Ask Pangea for help** button, with the user's email filled in when the app knows it. The request reaches support@pangea.chat through the CMS ([form-submissions](../../../cms/.github/instructions/form-submissions.instructions.md#network-help-requests) lists what it carries). Only these requests email the team, which keeps the volume low, and each account can send one a day.

If the CMS is blocked too, the request waits on the device until it can be sent, and the user sees it waiting, then sent. If the CMS answers with an error, the user is asked to email support@pangea.chat, and the app tries to send the request once more the next time it starts.

**Sentry.** The app reports each blocked server to Sentry once per session, tagged with the user's courses, so a class's reports lead to its teacher. It adds no personal data beyond the account ID and, on the web, the IP address that every report carries, and not the network's name. A lost connection on an online device is reported once per session; an offline device reports nothing, because there is nothing for us to fix.

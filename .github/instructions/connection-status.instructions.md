---
applyTo: "lib/features/connection_status/**"
description: "How the app tells the user it cannot reach a server it needs, what it tells them to do, and how the team hears about it."
---

# Connection status

When the app cannot reach a server it needs, it tells the user the cause, and what to do: if the device is offline, the user reconnects or waits; if our servers are down, the user waits for us; if the network blocks a server, as a school's Wi-Fi filter can, the user switches network or asks IT. It also reports the problems we can fix to Sentry, and lets a user on a blocked network ask us for help.

## Servers the app needs

- The chat server: everything, from sign-in to chat and courses.
- The Pangea API, which includes the CMS: the language tools, activities and subscriptions.
- The image server: activity and course images.
- YouTube: activity videos.
- The map server: the world map.
- Google or Apple sign-in ([signup-and-login](signup-and-login.instructions.md)): signing in that way; email sign-in still works.

Without the chat server or the Pangea API the app stops; without any other server, only its feature breaks.

## Telling the causes apart

The app tells three problems apart: the device is offline, the network blocks a server the app needs, or the server itself is down.

When the phone, computer or browser reports that the device is not connected to any network, the app shows that it is offline at once.

Otherwise, when a request fails, the app checks the server it was meant for:

- If the server replies, even with an error, or does not reply within a few seconds, the network is not blocking it.
- If the server refuses the connection, or another site replies in its place, the app asks a neutral address that filters let through. If that fails too, the device is offline. If it replies, the network is blocking the server.

Our own servers, the chat server and the Pangea API, are the exception. A deploy makes them refuse connections for a minute or more, as a filter does. So when one of them refuses, the app first treats it as an outage and asks again every 30 seconds. If the server still refuses after three minutes, the app concludes that the network is blocking it.

When messages stop arriving from the chat server, the app also asks the neutral address. If it replies, the banner says the app can't reach Pangea Chat. If not, it says the device is offline.

While the app is in the background, out of sight, nothing it sees counts, because the device pauses its requests and they fail as if refused. On the web, the browser hides who answered, so only a refused connection counts as a block, and a filter that shows its own block page is missed.

**Before sign-in.** With no messages to watch, the banner relies on whether the device is connected to a network and on the check a failed sign-in starts. A failed sign-in that cannot reach the chat server says so at once, so nobody waits three minutes to learn that something is wrong; the sign-in form still shows its own error.

## What the user sees

Connection issues reach users in two places: a note or error in the view they affect, or a banner at the top of the page. Two different banners share that slot at the top of every page, and only one shows at a time:

- The connection banner says the device is offline, or that the app can't reach Pangea Chat, and "Back online" when the connection returns. It follows only the chat server and the device's own network report, not the Pangea API or any other server.
- The filtered-network banner says this network is blocking Pangea Chat, with a button that opens the guidance. It shows when the network blocks the chat server or the Pangea API, and it wins over the connection banner, because the user can act on it.

Either banner can be dismissed, and comes back when its news changes. An outage of any other server shows only that feature's own error.

### A blocked network

The guidance tells a user on a phone (the iOS and Android apps, and phone browsers) to turn off Wi-Fi and use mobile data, and a user on any other device to use a phone's hotspot. A section for everyone, so the app need not know who is a teacher, gives IT staff the domains to allowlist, with a copy button.

When only another server is blocked, its feature shows a short note in its place, in an activity or on the world map, that opens the same guidance, and the rest of the screen works. On the web, a blocked Google or Apple sign-in shows a dialog that offers email sign-up instead ([signup-and-login](signup-and-login.instructions.md)).

### Practice while you wait

Both banners offers vocab practice, which runs offline ([practice-exercises](practice-exercises.instructions.md#offline-practice)), to a signed-in learner the app does not know to be unsubscribed, with a full session's worth of words whose meanings are saved on the device, unless practice is in progress or open.

## Repair

### Reconnecting

When the connection to the chat server returns, the connection banner says "Back online" for a few seconds. A block clears once a request to its server succeeds, and a network change runs the check again, so a user who switches to mobile data carries on without restarting. The map is the exception: the browser can show a saved tile on a network that blocks the map, so a tile that loads starts a check instead.

### Reporting to the team

**Asking Pangea for help.** The guidance ends with the user's email, filled in from the account when the app has one, and an **Ask Pangea for help** button. The request reaches support@pangea.chat as a CMS form submission ([form-submissions](../../../cms/.github/instructions/form-submissions.instructions.md#network-help-requests) lists what it carries). The team is emailed about a block only when someone asks, which keeps the volume low. Each account can send at most one a day.

When the CMS is blocked too, the request waits on the device for the next good connection, and the user sees it waiting, then sent. If the CMS answers with an error, the guidance asks the user to email support@pangea.chat. The request stays on the device, and the app tries to send it once more the next time it starts.

**Sentry.** Each block the app finds reports one Sentry error per server per session, tagged with the user's courses, so one class's reports gather under its course, which leads to its teacher. It adds no personal data beyond what every client event carries (the account ID and, on the web, the IP address), and not the network's name. A lost connection on an online device reports one Sentry warning per session; an offline device reports nothing, because there is nothing for us to fix.

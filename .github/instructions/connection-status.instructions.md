---
applyTo: "lib/features/connection_status/**"
description: "How the app determined that it cannot reach a server, what it shows the user, and how the team hears about it."
---

# Connection status

When the app cannot reach a server, it tells the user the cause and next steps: if the device is offline, reconnect or wait; if servers are down, wait; if the network blocks a server, switch network or ask IT. The app reports blocks and chat-server outages to Sentry (not offline devices), and lets a user on a blocked network ask the team for help.

## Servers the app needs

What each server provides:

- Chat server (Synapse): sign-in, messaging, courses and chats. Without it, the app stops.
- Pangea API: language tools, activities, subscriptions, course and activity content. Without it, the app stops.
- Image server: activity and course images.
- YouTube: activity videos.
- Map server: the world map.
- Google and Apple sign-in ([signup-and-login](signup-and-login.instructions.md)): signing in that way; email sign-in still works.

## Telling the causes apart

The app compares the server it needs with a neutral address: one that phones and computers use to check that they are online, which filters let through. It checks after a request gets no response, when messages stop arriving, when an activity video opens, and before Google or Apple sign-in on the web.

Offline device:
- The device reports that it has no network.
- Requests to a server and to the neutral address both fail.

Server outage:
- The server answers with an error, or too slowly.
- Messages stop arriving from the chat server while the neutral address answers.

Network block:
- The server refuses the connection, or another site answers in its place, while the neutral address answers. The chat server and the Pangea API refuse connections for a minute or more while they update, so a refusal from either counts as a block only after three minutes.
- On the web, the app cannot see a filter's block page, so it misses filters that show one instead of refusing the connection.

Nothing counts while the app is out of sight, because the device may pause it, so coming back never raises a false alarm.

**Before sign-in.** With no messages to watch, the banner relies on the device's network status and on failed sign-ins. It says at once when a sign-in cannot reach the chat server, so nobody waits three minutes; the sign-in form still shows its own error.

## What the user sees

A banner shows at the top of the page. One of the following:

- The connection banner says the device is offline or the app can't reach Pangea Chat, then "Back online" when the connection returns. It follows only the chat server and the device's network status.
- The filtered-network banner says this network is blocking Pangea Chat. It shows when the network blocks the chat server or the Pangea API, and wins over the connection banner, because the user can act on it.

Both offer offline vocab practice to users who qualify ([practice-exercises](practice-exercises.instructions.md#offline-practice)).

When the image server, YouTube or the map is blocked, a note takes that feature's place and the rest of the screen works. On the web, a blocked Google or Apple sign-in offers email sign-up instead ([signup-and-login](signup-and-login.instructions.md)).


The filtered-network banner's button and each note open the same guidance: on a phone, in the app or its browser, switch from Wi-Fi to mobile data; on any other device, use a phone's hotspot. It also lists the domains for IT staff to allow, shown to everyone so the app need not know who is a teacher.

## Repair

### Reconnecting

When the connection to the chat server returns, the connection banner says "Back online" for a few seconds. A block on the chat server or the Pangea API clears once a request to it succeeds. Any other block clears only when a later check finds the server reachable. 

A network change checks every blocked server again, so a user who switches to mobile data carries on without restarting. When map pieces load while the map is marked blocked, the app checks the map server again before removing the note, because the browser may be showing pieces it saved earlier. Images get no such check, so an image block usually lasts until the network changes.

### Reporting to the team

The guidance ends with an **Ask Pangea for help** button, with the user's email pre-filled. The request reaches support@pangea.chat through the CMS ([form-submissions](../../../cms/.github/instructions/form-submissions.instructions.md#network-help-requests)). It also carries the IDs of the user's courses. Each account can send one email a day.

If the CMS is blocked too, the request waits on the device until it can be sent, and the user sees it waiting, then sent. If the CMS answers with an error, the user is asked to email support@pangea.chat, and the app tries to send the request once more the next time it starts.

The app also reports each blocked server to Sentry once per session, tagged with the user's courses, so a class's reports lead to its teacher. It adds no personal data beyond the account ID and, on the web, the IP address that every report carries, and not the network's name. A lost connection on an online device is reported once per session; an offline device reports nothing.

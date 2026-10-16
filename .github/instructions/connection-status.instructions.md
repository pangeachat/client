---
applyTo: "lib/features/connection_status/**"
description: "How the app tells the user it cannot reach Pangea (their device is offline, Pangea is down, or the network blocks Pangea), what it tells them to do, and how the team hears about it."
---

# Connection status

When the app cannot reach Pangea, the user should know, and know which of three causes it is, because each has a different fix:

- **The device is offline.** The user reconnects, or waits.
- **Pangea is down.** The user waits while we fix it.
- **The network blocks Pangea.** School and district Wi-Fi filters, such as Securly, can block hosts the app needs. The user switches network or asks IT. Teachers who come to us from conference booths are often on these networks.

Without a check, every one of these looks like a generic failure, and the team never hears about a filtered network. So the app tells the causes apart, tells the user what they can do now, reports what we can act on to Sentry, and lets a user on a filtered network ask the team for help.

## Hosts the app needs

| Category | Production host | What breaks when it is blocked |
|---|---|---|
| Chat server | `matrix.pangea.chat` | Everything: sign-in, chat, courses |
| Pangea API | `api.pangea.chat` | The language tools, activities and subscriptions |
| Images | `content.pangea.chat` | Activity and course images |
| Video | YouTube | Activity videos |
| Map | `tiles.stadiamaps.com` | The world map background |
| Sign-in providers | Google and Apple sign-in | Google and Apple sign-in; email sign-in still works |

A blocked chat server or Pangea API stops the app. Any other blocked host breaks one feature, and the rest of the app keeps working. When the app starts to depend on a new host, add it here and to the domain list the app shows IT staff.

## Telling the causes apart

The check runs only when something has already gone wrong, so a healthy network never pays for it:

- when the connection to the chat server is lost (see [Losing the connection](#losing-the-connection));
- after a request to one of these hosts fails without any response;
- when an activity with a video opens, because the video plays in an embedded page whose failures the app cannot see;
- before Google or Apple sign-in starts on the web ([signup-and-login](signup-and-login.instructions.md)).

[`FilteredNetworkController`](../../lib/features/connection_status/filtered_network_controller.dart) asks the needed host first. Only when that fails does it ask a neutral host: the address that phones and computers use to decide whether they are online. Filters let that address through, because blocking it makes every device on the network report "no internet".

| Neutral host | Needed host | Verdict | The user sees |
|---|---|---|---|
| No answer | Any | Offline | The offline banner, when the chat server is the host that failed |
| Answers | Connection refused, or answered by a site that is not ours | Filtered | Filtered-network guidance |
| Answers | Slow, or an error from our own server | Outage or slow network | The "can't reach" banner for the chat server; the feature's own error for any other host |

A Pangea outage usually shows as a slow answer or an error from our own servers. A deploy is the exception: while the chat server restarts, it refuses connections for a minute or more, which looks the same as a filter. So a refused connection to the chat server or the Pangea API counts as a block only when it holds for three minutes. The app checks again every 30 seconds, and any answer in that time means our server was restarting. The guidance and the Sentry report for those two hosts therefore appear about three minutes after the first failure. Every other host, and the sign-in check, is decided on the first check: a deploy does not restart them, and sign-in cannot wait.

Nothing a check sees while the app is in the background counts, for the same reason the connection banner ignores those failures: the operating system pauses a backgrounded app's requests, and they fail as if refused. So no check starts in the background, and a check whose answer comes back there reaches no verdict: nothing is marked blocked or reported. The three-minute hold counts only time in the foreground. A recheck due while the app is in the background is skipped, and the hold goes on when the app comes back. Coming back starts no check of its own; the next failed request starts one, as at any other time.

A slow answer is never a block, the same rule the sign-in check uses. A web browser hides who answered a request, so on the web only a refused connection counts, and a filter that serves its own block page is missed there.

The verdict clears as soon as a request to the blocked host succeeds, and the check runs again when the device changes network. A user who switches to mobile data carries on without restarting the app.

## Losing the connection

The connection to the chat server runs the whole time the app is open, and it retries every few seconds when it fails, so it is the first thing to notice a lost connection. The app treats the connection as lost after two failed attempts in a row. It ignores a single failure, because flaky connections drop one now and then. When the device itself reports no network, the app treats the connection as lost at once. That report is the faster signal: a dead connection can otherwise take up to the request timeout of about 35 seconds to fail. Failures while the app is in the background do not count, because the operating system pauses a backgrounded app's requests. [`ConnectionStatusController`](../../lib/features/connection_status/connection_status_controller.dart) makes this decision.

Once the connection is lost, the app runs the check above on the chat server and shows the result in the connection banner:

| Verdict | The banner says |
|---|---|
| Offline | You're offline. Pangea Chat will reconnect when your connection is back. |
| Device online, chat server not answering or returning errors | Can't reach Pangea Chat. Trying again… |
| Filtered | Nothing; the filtered-network banner below takes over |

A refused connection that has not yet held for three minutes (a deploy restarting the chat server, as above) shows as "Can't reach Pangea Chat". When the connection comes back, the banner says "Back online" for a few seconds and goes away.

## What the user sees

The connection banner and the filtered-network banner share one slot at the top of the app ([`ConnectionBanner`](../../lib/features/connection_status/widgets/connection_banner.dart)). The filtered-network banner wins, because the user can act on it. Both can be dismissed: they float over the top of the page, and while offline the user may still need what is underneath, such as chats they have already opened. A dismissed connection banner comes back when the state changes, from offline to "can't reach" or the other way, or when the connection returns and is lost again.

The connection banner is the one connection indicator on every layout. The chat header does not show sync status.

**Practice while you wait.** While the connection banner says the app is offline or can't reach Pangea Chat, or the filtered-network banner is up, the banner offers **Practice vocab while you wait** on a row of its own under the message. The offer shows only when all of these are true: this device has a full session's worth of words (10) whose meanings are saved on it, the app does not know the learner to be unsubscribed, no practice session is in progress, and the practice page is not open. Tapping it dismisses the banner, which floats over the top of the page and would otherwise cover the practice header. It then opens vocab practice, which runs offline ([practice-exercises](practice-exercises.instructions.md#offline-vocab-practice)).

When the chat server or the Pangea API is blocked, the filtered-network banner says that this network is blocking Pangea Chat. It comes back after a dismissal when another host is blocked. Its button opens the guidance, with the advice for this device:

- **Phone** (the iOS and Android apps, and phone browsers): turn off Wi-Fi and use mobile data.
- **Any other device**: connect to a phone's hotspot.
- **For teachers and IT staff**, under its own heading for everyone: the domains to allowlist, with a copy button. The app does not need to know who is a teacher.

When only a feature host is blocked, that feature shows a short note ([`FilteredNetworkNote`](../../lib/features/connection_status/widgets/filtered_network_note.dart)) and the rest of the screen works. An activity whose video is blocked opens without the video and says that the network blocks it. Tapping a note opens the same guidance. A blocked sign-in provider keeps its existing dialog, which offers email sign-up.

## Sentry

Each filtered verdict reports one Sentry error per host category per session, tagged with the category, the platform, the network type (Wi-Fi, mobile data, wired or unknown) and the IDs of the courses the user has joined, so the reports from one class gather under its course, and the course leads to its teacher. It adds no personal data to what every client event already carries, which is the account ID and, on the web, the IP address. It does not record the network's name. On the phone apps, an event that cannot be sent waits on the device and goes out on the next good connection. The web app has no such store, so an event it cannot send is lost; the help request below is the user's way to reach us from there.

The once-per-session "no response" warning in [repos-and-error-handling](repos-and-error-handling.instructions.md) stays; the filtered verdict is the event that says why.

A lost connection where the device is online but the chat server is not answering reports one Sentry warning per session, tagged with the platform and the network type. It is real users' view of an outage, and it can catch a regional or DNS failure that our server-side checks miss. A lost connection on an offline device reports nothing, because there is nothing for us to fix.

## Asking Pangea for help

The guidance ends with a short form: the user's email address, filled in from the account when the app has one, and an **Ask Pangea for help** button. The help request carries that email, the account ID when signed in, the blocked categories, the platform, the network type and the time the block was first seen.

The team hears about a block only when someone asks. The user chooses what is sent, and the volume stays low: a class of 30 behind one filter sends a request only from whoever taps the button, usually the teacher. The app sends at most one help request a day from each device. A limit per school network is not possible, because the device cannot learn which network it is on without reaching our servers, and a waiting request reaches us from a different network.

The request goes to the CMS as a form submission, and the CMS's existing team notification emails it to support@pangea.chat ([form-submissions](../../../cms/.github/instructions/form-submissions.instructions.md)). When the CMS is blocked too, the request waits on the device and goes out on the next good connection, usually once the user is on mobile data or a hotspot. The user sees that it is waiting, and then that it was sent. If the CMS refuses it, the guidance asks the user to email support@pangea.chat instead, and [`NetworkHelpRepo`](../../lib/features/connection_status/network_help_repo.dart) does not try again until the next session.

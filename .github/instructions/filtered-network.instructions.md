---
applyTo: "lib/features/network_filter/**"
description: "How the app tells a filtered network apart from being offline or a Pangea outage, what it tells the user to do, and how the team hears about it."
---

# Filtered networks

School and district Wi-Fi filters, such as Securly, can block hosts the app needs. Without a check, the user sees a generic failure and the team never hears about it. Teachers who come to us from conference booths are often on these networks.

When a network blocks a host the app needs, the app tells the user what they can do now, reports the block to Sentry, and lets the user ask the team for help.

## Hosts the app needs

| Category | Production host | What breaks when it is blocked |
|---|---|---|
| Chat server | `matrix.pangea.chat` | Everything: sign-in, chat, courses |
| Pangea API | `api.pangea.chat` | The language tools, activities and subscriptions |
| Images | `content.pangea.chat` | Activity and course images |
| Video | YouTube | Activity videos |
| Map | `tile.openstreetmap.org` | The world map background |
| Sign-in providers | Google and Apple sign-in | Google and Apple sign-in; email sign-in still works |

A blocked chat server or Pangea API stops the app. Any other blocked host breaks one feature, and the rest of the app keeps working. When the app starts to depend on a new host, add it here and to the domain list the app shows IT staff.

## Detecting a block

The check runs only when something has already gone wrong, so a healthy network never pays for it:

- after a request to one of these hosts fails without any response;
- when an activity with a video opens, because the video plays in an embedded page whose failures the app cannot see;
- before Google or Apple sign-in starts on the web ([signup-and-login](signup-and-login.instructions.md)).

[`FilteredNetworkController`](../../lib/features/network_filter/filtered_network_controller.dart) asks the needed host first. Only when that fails does it ask a neutral host: the address that phones and computers use to decide whether they are online. Filters let that address through, because blocking it makes every device on the network report "no internet".

| Neutral host | Needed host | Verdict | The user sees |
|---|---|---|---|
| No answer | Any | Offline | The app's usual offline behavior |
| Answers | Connection refused, or answered by a site that is not ours | Filtered | Filtered-network guidance |
| Answers | Slow, or an error from our own server | Outage or slow network | The app's usual error |

A Pangea outage shows as a slow answer or an error from our own servers, so an outage never sends every user the filtered-network message. A slow answer is never a block, the same rule the sign-in check uses. A web browser hides who answered a request, so on the web only a refused connection counts, and a filter that serves its own block page is missed there.

The verdict clears as soon as a request to the blocked host succeeds, and the check runs again when the device changes network. A user who switches to mobile data carries on without restarting the app.

## What the user sees

When the chat server or the Pangea API is blocked, a banner ([`FilteredNetworkBanner`](../../lib/features/network_filter/widgets/filtered_network_banner.dart)) at the top of the app says that this network is blocking Pangea Chat. The user can dismiss it; it comes back when another host is blocked. Its button opens the guidance, with the advice for this device:

- **Phone** (the iOS and Android apps, and phone browsers): turn off Wi-Fi and use mobile data.
- **Any other device**: connect to a phone's hotspot.
- **For teachers and IT staff**, under its own heading for everyone: the domains to allowlist, with a copy button. The app does not need to know who is a teacher.

When only a feature host is blocked, that feature shows a short note ([`FilteredNetworkNote`](../../lib/features/network_filter/widgets/filtered_network_note.dart)) and the rest of the screen works. An activity whose video is blocked opens without the video and says that the network blocks it. Tapping a note opens the same guidance. A blocked sign-in provider keeps its existing dialog, which offers email sign-up.

## Sentry

Each filtered verdict reports one Sentry error per host category per session, tagged with the category, the platform and the network type (Wi-Fi, mobile data, wired or unknown). It adds no personal data to what every client event already carries, which is the account ID and, on the web, the IP address. It does not record the network's name. On the phone apps, an event that cannot be sent waits on the device and goes out on the next good connection. The web app has no such store, so an event it cannot send is lost; the help request below is the user's way to reach us from there.

The once-per-session "no response" warning in [repos-and-error-handling](repos-and-error-handling.instructions.md) stays; the filtered verdict is the event that says why.

## Asking Pangea for help

The guidance ends with a short form: the user's email address, filled in from the account when the app has one, and an **Ask Pangea for help** button. The help request carries that email, the account ID when signed in, the blocked categories, the platform, the network type and the time the block was first seen.

The team hears about a block only when someone asks. The user chooses what is sent, and the volume stays low: a class of 30 behind one filter sends a request only from whoever taps the button, usually the teacher. The app sends at most one help request a day from each device. A limit per school network is not possible, because the device cannot learn which network it is on without reaching our servers, and a waiting request reaches us from a different network.

The request goes to the CMS as a form submission, and the CMS's existing team notification emails it to support@pangea.chat ([form-submissions](../../../cms/.github/instructions/form-submissions.instructions.md)). When the CMS is blocked too, the request waits on the device and goes out on the next good connection, usually once the user is on mobile data or a hotspot. The user sees that it is waiting, and then that it was sent. If the CMS refuses it, the guidance asks the user to email support@pangea.chat instead, and [`NetworkHelpRepo`](../../lib/features/network_filter/network_help_repo.dart) does not try again until the next session.

---
applyTo: "lib/routes/home/**"
description: "Design for the pre-authentication experience — the intro carousel over the map backdrop, its responsive layout and spacing, and the choice between signup and login."
---

# Signup and Login

Everything a person sees before they have an account: the intro carousel that pitches the app, the choice between Get started that direct to Sign up options page or Login that direct to Login options page.

See also: [returning-user-detection.instructions.md](returning-user-detection.instructions.md) | [matrix-auth.instructions.md](matrix-auth.instructions.md) | [world-map-tiles.instructions.md](world-map-tiles.instructions.md)

## Goals

- The screen looks like the app it introduces, so arriving on the world map afterwards is not a visual surprise.
- A first-time visitor understands what Pangea Chat is through the carousel before reaching Get started CTA.
- A returning visitor reaches their previous login method with Login CTA.

## The intro carousel

[`LoginOrSignupView`](../../lib/routes/home/login_or_signup_view.dart) is the landing screen for anyone without a session. Six slides advance on their own every eight seconds and can also be swiped, so the story plays for a passive viewer and stays steerable for an active one.

### Map backdrop

The screen sits on the world map rather than on a flat surface colour, so the first thing a new user sees is the surface they will land on after onboarding. The backdrop is a static image rather than a live tile: this screen has no session, and spending tile requests on decoration would draw down the budget described in [world-map-tiles.instructions.md](world-map-tiles.instructions.md) for people who have not signed up yet.

The backdrop also carries the leftover space on wide windows. Because a slide is capped rather than stretched, there is always area around it, and that area reads as part of the product instead of as an empty margin.

### Layout and responsiveness

The screen chooses between two layouts from the window's **shape**, not the device: when height divided by width is greater than 1.75 it uses the narrow layout. A tall phone and a narrowed desktop browser therefore get the same treatment, which is what someone resizing a window expects. This is deliberately not the app-wide column breakpoint in [`FluffyThemes`](../../lib/config/themes.dart), which switches on width alone — that rule decides how many panes fit side by side, a question this single-column screen does not ask.

| | Narrow (ratio above 1.75) | Wide (ratio 1.75 or below) |
|---|---|---|
| Slide crop | Tall | Wide, without padding |
| Slide width | Full window width | Capped at 600 |
| Slide height | Width times 1.25 | Two thirds of the space below the header |
| Brand header | None — the first slide carries the name | Pangea logo at 48 beside the wordmark |
| Headline | Over the artwork | Below the artwork |
| Fallback logo when an image fails | 128 | 256 |

One slide is always full-bleed across the carousel; slides never peek in from the edges, so a partly visible neighbour cannot be mistaken for content.

Spacing below is in logical pixels, as currently built. The three stacked gaps of 24 between carousel, dots and buttons are what keep the dots reading as a group with the carousel rather than with the buttons.

| Gap | Narrow | Wide |
|---|---|---|
| Above and below the brand header | — | 32 above, 24 below |
| Reserved strip below artwork for the headline | 32 | — |
| Headline inset from the slide edge | 10 bottom, 20 each side | 24 above the headline |
| Carousel to dots | 24 | 24 |
| Dot size, and gap either side of each dot | 8, with 4 | 8, with 4 |
| Dots to buttons | 24 | 24 |
| Button column width | Capped at 300 | Capped at 300 |
| Button column side padding | 24 | 24 |
| Between the two buttons | 8 | 8 |
| Inside each button | 16 | 16 |

On wide windows the carousel takes twice the vertical space of the button area beneath it.

### Slide text

Each headline is localized text drawn over the artwork rather than baked into it, so it translates and scales independently of the image, and a copy change never means re-exporting six files. In the narrow layout the headline sits at the top of the slide, above the device mockup, so it is read before the image and stays clear of the buttons.

Over a busy map, legibility comes from a scrim or outline behind the text rather than from darkening the type, so the same treatment survives a change of background artwork. Headlines do not scale with the operating system's text-size setting, because the strip reserved for them is fixed and overflowing text would collide with the artwork and the buttons.

### Slide images

Slides are fetched at runtime from the assets bucket named in [`AppConfig`](../../lib/config/app_config.dart), by a filename encoding the slide number and the crop, so each layout loads only the crop it needs.

Hosting the slides remotely rather than bundling them means the feature story can be refreshed without an app release — which matters because the slides show real product UI, and that UI keeps changing. The cost is a live dependency: a stale or unreachable bucket reaches every user at once, so a failed image falls back to the Pangea logo rather than a broken-image box.

## Buttons, dots and colour

Get started and Login to my account sit together beneath the carousel on every slide. New users are prioritised by visual weight rather than by hiding the login path, because a returning user who reinstalled should not have to reach the end of a pitch to find their way back in.

Colour comes from the Material 3 scheme built in [`FluffyThemes`](../../lib/config/themes.dart), which derives every role from a single seed — the purple in [`AppConfig`](../../lib/config/app_config.dart), stored as a setting so it can change. Use the scheme roles below rather than literal hex values: roles resolve correctly again when the seed changes and when the theme switches to dark.

| Element | Scheme role | Why |
|---|---|---|
| Get started | `primaryContainer` on `onPrimaryContainer` | Filled and highest contrast — the path most visitors should take |
| Login to my account | `surface` on `onSurface`, 40%| Present as CTA button quieter. Button color as 40% opacity rather than no color, because it need to be readable when overlay complex map background  |
| Active dot | `primary` | Matches the brand accent so position is readable at a glance |
| Remaining dots | `outlineVariant` | Visible enough to count, quiet enough not to compete with the buttons |
| Headline | `onSurface` | Carried over the map by a scrim, not by a darker colour |

Both buttons share the corner radius defined in `AppConfig`, so they read as one control group rather than two unrelated shapes. The dots are fully rounded and cross-fade between the two roles when the slide changes, so the transition is visible without being animated distraction.

## Design refer in Figma

[Signup and Login](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=14378-43729)

The comps cover the narrow layout only, mobile-first. The wide layout follows the rules in the tables above, which stand as its specification until a comp exists.

## Choosing a method

Signup and login are separate destinations offering the same three methods: Apple, Google and email. Each creates a distinct Matrix account, which is why the method chosen the first time matters enough to remember.

[`SignupPageView`](../../lib/routes/home/signup/signup_view.dart) carries the terms-of-service indicator; [`LoginOptionsView`](../../lib/routes/home/login/login_options_view.dart) does not, because agreement is collected once at account creation.

When a previous method is known, both screens name it. Login dims the other two options to guide without removing them; signup goes further and links across to login, since someone who already has an account has usually landed on the wrong screen. Neither screen removes an option, because the stored hint can be wrong and a person may intend a different method.

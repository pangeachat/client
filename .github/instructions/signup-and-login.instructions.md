---
applyTo: "lib/routes/home/**"
description: "Design for the pre-authentication experience — the intro carousel, its per-layout backdrops, responsive layout and type, the slide assets, and the choice between signup and login."
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

### Backdrops

**Each layout gets a different backdrop.** The narrow layout sits on the world map, so the first thing a new user sees is the surface they will land on after onboarding. The wide layout sits on a star field instead, because a wide carousel image already fills its own frame and a map behind it would read as a second subject competing with the slide rather than a setting for it.

| Layout | Backdrop | Files |
|---|---|---|
| Narrow | World map | [`world-map-background.svg`](../../assets/pangea/world-map-background.svg) and [`world-map-background-dark.svg`](../../assets/pangea/world-map-background-dark.svg) |
| Wide | Stars over a base colour that follows the theme | [`star_background.png`](../../assets/pangea/star_background.png) |

**Where the map files come from.** Both are vendored copies of [`world-map-background.svg`](https://github.com/pangeachat/business/blob/main/brand/world-map-background.svg) and [`world-map-background-dark.svg`](https://github.com/pangeachat/business/blob/main/brand/world-map-background-dark.svg) in `pangeachat/business`, which is the source of truth for the artwork and for the `Map Land` / `Map Water` color tokens behind it. Refresh them by copying both files out of `business/brand/` into `assets/pangea/`; never edit them here, or the two repos drift.

The client deliberately does **not** load these from `https://assets.pangea.chat/brand/`, where the same files are also published. Flutter bundles assets into the binary at build time, and this screen paints before the app has made any network call, so a remote URL would have nothing to fall back to. That is the same reasoning the website applies to its own copy.

The star field needs only one file where the map needs two. It is a transparent image carrying nothing but the stars, so the base colour beneath it flips with the theme while the stars stay as they are. The map fills its whole frame with land and water, so it needs a second file in dark tones — there is no base showing through to do that work. Both map files are vector, two flat fills each, so the dark variant is the light one with its water and land fills swapped.

The stars also give the wide layout something to fill the space around a slide with. Because a slide is capped rather than stretched, a broad window always leaves area around it, and that area now reads as part of the product rather than as an empty margin.

Both backdrops are static images rather than live map tiles. This screen has no session, and spending tile requests on decoration would draw down the budget described in [world-map-tiles.instructions.md](world-map-tiles.instructions.md) for people who have not signed up yet.

Unlike the slides, all three files are bundled with the app rather than fetched. They do not change when features change, so the tradeoff runs the other way: a backdrop is worth pinning to the release to get an instant, offline-safe first screen.

### Layout and responsiveness

The screen chooses between two layouts from the window's **shape**, not the device: when height divided by width is greater than 1.75 it uses the narrow layout. A tall phone and a narrowed desktop browser therefore get the same treatment, which is what someone resizing a window expects. This is deliberately not the app-wide column breakpoint in [`FluffyThemes`](../../lib/config/themes.dart), which switches on width alone — that rule decides how many panes fit side by side, a question this single-column screen does not ask.

| | Narrow (ratio above 1.75) | Wide (ratio 1.75 or below) |
|---|---|---|
| Slide crop | Tall | Wide |
| Slide width | Full window width | Open — see Wide layout sizing below |
| Slide height | Width times 1.25 | Open — see Wide layout sizing below |
| Brand header | None — the first slide carries the name | None — the first slide carries the name |
| Headline | Above the carousel image | Above the carousel image |
| Fallback logo when an image fails | 128 | 256 |

One slide is always full-bleed across the carousel; slides never peek in from the edges, so a partly visible neighbour cannot be mistaken for content.

#### Wide layout sizing

On a wide window the carousel should be as large as the window allows while Get started and Login to my account stay fully visible beneath it. The buttons are what the screen is for; the carousel is the pitch. Nothing about a slide justifies clipping a button or pushing it out of view.

Three things bound how large that can be:

- **The wide carousel image is 1200 × 600 and must not be cropped.** Each slide is a single composed image, so cropping removes content rather than trimming a margin.
- **The space around a slide should read as deliberate.** The report behind [#7415](https://github.com/pangeachat/client/issues/7415) was that web has too much empty space, so leaving slides small and centred is not the answer. A slide pressed hard against the window edges or against the buttons looks equally unfinished.
- **The shipped cap of 600 is too small.** Whatever replaces it is larger. 840 has been suggested because it matches the width at which [`FluffyThemes`](../../lib/config/themes.dart) already treats a window as wide enough for side-by-side panes.

**Whether this is achieved with a width cap, with padding, or as a proportion of the window — and the exact numbers — is left open to the implementing developer.** How the slide, dots and buttons share the vertical space is easier to judge in the running app at real window sizes than in a comp. The wide frames in the Figma reference show the balance being aimed for.

The number should not come from `MaxWidthBody` in [layout.instructions.md](layout.instructions.md). That default is a reading measure, sized so a line of prose stays comfortable; a slide is an image rather than prose, so aligning to it for consistency's sake would reintroduce the empty space this is meant to fix.

Once it ships, ping @KhueDao1 with the values used and this section is updated to record them.

Spacing below is in logical pixels and applies to both layouts. The three stacked gaps of 24 between carousel, dots and buttons are what keep the dots reading as a group with the carousel rather than with the buttons.

| Gap | Value |
|---|---|
| Around the carousel group — slides, headline and dots together | 32 above, 24 below |
| Strip reserved for the headline above the carousel image | 64, growing if scaled text needs it |
| Headline inset from the top of the slide | 16 |
| Headline side margins | 20 each side |
| Between the headline and the carousel image | 24 |
| Carousel to dots | 24 |
| Dot size, and gap either side of each dot | 8, with 4 |
| Dots to buttons | 24 |
| Button column width | Capped at 300 |
| Button column side padding | 24 |
| Between the two buttons | 8 |
| Inside each button | 16 |

### Slide text

Each headline is localized text drawn over the carousel image rather than baked into it, so it translates and scales independently of the image, and a copy change never means re-exporting six files.

**The headline sits above the carousel image in both layouts**, at the top of the slide, so it is read before the image and stays clear of the buttons. Nothing about the headline changes with window shape — the tables above give the measurements, and only the spacing around it differs.

| Property | Value |
|---|---|
| Typeface | Roboto |
| Weight | Semi-bold |
| Size | 24 |
| Alignment | Centred |
| Wrapping | Up to two lines |

Size and weight are the same in both layouts — a headline that changes weight with window shape reads as a different voice for the same sentence.

Colour and outline come from the scheme roles under Buttons, dots and colour. In the narrow layout the outline does the separating work over the map: taking the surface colour makes it near-white in light and near-dark in dark, so one rule holds in both themes.

**A headline wraps to a second line rather than shrinking or clipping**, because the size is doing legibility work over the carousel image. The strip is sized for two lines: one line at 24 measures 29, so two with the same breathing room is 64. Where the operating system's text-size setting needs more, the strip grows and the carousel image gives up the height — which is what makes it safe to leave scaling enabled. The current build disables it instead, recorded in [issue #6294](https://github.com/pangeachat/client/issues/6294).

Two lines is headroom for translation, not a target. **A headline should still read as one line at 24 in English** so longer languages have somewhere to go; several run twenty to thirty per cent longer. A third line means the copy is too long.

### Image assets

Slides are fetched at runtime from the bucket named in [`AppConfig`](../../lib/config/app_config.dart):

`https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com`

Files are named `Carousel_<number>_<crop>_<version>.png`. The number runs 1 to 6, the crop is `ratio4x5` for the narrow layout or `ratio2x1` for the wide one, and the version marks the design generation — currently `V5`. Twelve files make a full set.

The version suffix means a new set is added alongside the one it replaces rather than overwriting it, so the previous carousel images stay retrievable if a slide has to be rolled back or compared. It also makes the files safe to cache forever, since a new generation never reuses an old name.

The client still composes the legacy wide name `ratio2x1_NoPadding` and no version token, so **it switches to `ratio2x1_V5`** as part of [#7415](https://github.com/pangeachat/client/issues/7415). Until then the files linked under Slide inventory are live in the bucket but unused.

### Slide inventory

A slide is two things kept in separate places: **the carousel image in the bucket, the headline in the code.** Carousel images are uploaded to AWS S3, so replacing one needs no release. A headline is a localized string, so changing one means a code edit, retranslation into every supported language, and a release. Reword a headline only when the wording is worth that; restyle or redraw a slide freely.

| # | Headline in code today | V5 headline | V5 carousel image |
|---|---|---|---|
| 1 | Learn a language while texting your friends! | none — carried in the carousel image | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_1_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_1_ratio2x1_V5.png) |
| 2 | Write and speak worry-free with Pangea Bot anytime, anywhere! | Explore, play and learn | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_2_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_2_ratio2x1_V5.png) |
| 3 | Join international learning communities, or start your own! | Conversation from Day One | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_3_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_3_ratio2x1_V5.png) |
| 4 | Play conversation games with the bot, classmates, and new friends! | Built for connection | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_4_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_4_ratio2x1_V5.png) |
| 5 | Jump into conversation from Day One with AI writing tools! | AI when you need it | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_5_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_5_ratio2x1_V5.png) |
| 6 | Play practice games personalized to your vocabulary and grammar needs! | Practice tailored for you | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_6_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_6_ratio2x1_V5.png) |

The V5 set is 800 x 1000 narrow and 1200 x 600 wide. Both land at roughly twice their on-screen size, which is what keeps the product UI inside the carousel image legible rather than soft — the complaint that opened [#7415](https://github.com/pangeachat/client/issues/7415).

Slide number in the filename is the position in this table, so carousel image and headline stay paired by number alone. Reordering the carousel therefore means renaming files as well as reordering the strings — cheaper to change what a slide says than where it sits.

Two things the V5 column changes beyond wording. **Slide 1 has no headline at all** — it opens on the brand line set inside the carousel image, so the layout must allow an empty headline rather than assume six. And **slides 3 and 4 swap subjects** against the current order, so the pairing above is the mapping to build to, not a rename of the existing strings. Both are copy and ordering changes rather than image changes, and both carry the release and translation cost described above.

For how a headline is set and how it behaves as the window changes, see Slide text and Layout and responsiveness.

Hosting the slides remotely rather than bundling them means the feature story can be refreshed without an app release — which matters because the slides show real product UI, and that UI keeps changing. The cost is a live dependency: a stale or unreachable bucket reaches every user at once, so a failed image falls back to the Pangea logo rather than a broken-image box.

## Buttons, dots and colour

Get started and Login to my account sit together beneath the carousel on every slide. New users are prioritised by visual weight rather than by hiding the login path, because a returning user who reinstalled should not have to reach the end of a pitch to find their way back in.

Colour comes from the Material 3 scheme built in [`FluffyThemes`](../../lib/config/themes.dart), which derives every role from a single seed — the purple in [`AppConfig`](../../lib/config/app_config.dart), stored as a setting so it can change. Use the scheme roles below rather than literal hex values: roles resolve correctly again when the seed changes and when the theme switches to dark.

| Element | Scheme role | Why |
|---|---|---|
| Get started | `primaryContainer` on `onPrimaryContainer` | Filled and highest contrast — the path most visitors should take |
| Login to my account | `surface` at 40% opacity, label `onSurface` | Present on every slide but quieter. Translucent in both layouts, so whatever sits behind it reads through and it does not float as a solid rectangle with no edge. Taking `surface` rather than a fixed white keeps it pale-translucent in light mode and dark-translucent in dark, so one value serves both themes |
| Active dot | `primary` | Matches the brand accent so position is readable at a glance |
| Remaining dots | `outlineVariant` | Visible enough to count, quiet enough not to compete with the buttons |
| Headline | `onPrimaryContainer` | The darkest tone of the brand hue, so the type holds against the map without introducing a colour outside the scheme |
| Headline outline | `surface` | Tracks the background rather than a fixed white, so the outline still separates the type when the theme flips to dark |

Both buttons share the corner radius defined in `AppConfig`, so they read as one control group rather than two unrelated shapes. The dots are fully rounded and cross-fade between the two roles when the slide changes, so the transition is visible without being animated distraction.

## Design refer in Figma

[Signup and Login](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=14478-25709)

That section holds both layouts — six narrow frames and six wide ones — so the wide layout is no longer specified by this doc alone.

The headline in the comps is drawn in a lighter purple than the role chosen above. Where the two disagree, the role wins — it keeps the screen inside one derived palette, and it follows the theme into dark mode on its own.

The comps also rewrite the headlines — shorter on slides 2 to 6, and absent on slide 1. Those are the intended wording; the strings listed under Slide inventory are what the code says today.

## Choosing a method

Signup and login are separate destinations offering the same three methods: Apple, Google and email. Each creates a distinct Matrix account, which is why the method chosen the first time matters enough to remember.

[`SignupPageView`](../../lib/routes/home/signup/signup_view.dart) carries the terms-of-service indicator; [`LoginOptionsView`](../../lib/routes/home/login/login_options_view.dart) does not, because agreement is collected once at account creation.

When a previous method is known, both screens name it. Login dims the other two options to guide without removing them; signup goes further and links across to login, since someone who already has an account has usually landed on the wrong screen. Neither screen removes an option, because the stored hint can be wrong and a person may intend a different method.

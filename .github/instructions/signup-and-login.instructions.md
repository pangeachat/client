---
applyTo: "lib/routes/home/**"
description: "Design for the pre-authentication experience — the intro carousel, its narrow-only map backdrop, responsive layout and type, the slide assets, and the choice between signup and login."
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

**The map backdrop belongs to the narrow layout only.** There, the screen sits on the world map rather than a flat surface colour, so the first thing a new user sees is the surface they will land on after onboarding. The wide layout keeps the plain surface background it uses today: the wide crop already carries its own full-bleed artwork, and a map behind it would compete rather than frame.

One consequence to keep in view: the wide layout's empty margin is therefore still empty. Because a slide is capped rather than stretched, there is always area around it on a broad window, and the backdrop is not what fills it. Anything done about that has to come from the cap or the crop, not from this image.

The backdrop is a static image rather than a live tile. This screen has no session, and spending tile requests on decoration would draw down the budget described in [world-map-tiles.instructions.md](world-map-tiles.instructions.md) for people who have not signed up yet.

There are **two backdrop files, not one** — [`world_map_background.png`](../../assets/pangea/world_map_background.png) for light and [`world_map_background_dark.png`](../../assets/pangea/world_map_background_dark.png) for dark — and the narrow layout picks one by theme brightness. A single light image would glare behind dark-mode UI, and it would defeat the headline outline described under Slide text, which takes the surface colour on the assumption that the backdrop moves with the theme.

Unlike the slides, both are bundled with the app rather than fetched. They do not change when features change, so the tradeoff runs the other way: the backdrop is worth pinning to the release to get an instant, offline-safe first screen, and it keeps signed-out visitors from spending tile requests on decoration.

### Layout and responsiveness

The screen chooses between two layouts from the window's **shape**, not the device: when height divided by width is greater than 1.75 it uses the narrow layout. A tall phone and a narrowed desktop browser therefore get the same treatment, which is what someone resizing a window expects. This is deliberately not the app-wide column breakpoint in [`FluffyThemes`](../../lib/config/themes.dart), which switches on width alone — that rule decides how many panes fit side by side, a question this single-column screen does not ask.

| | Narrow (ratio above 1.75) | Wide (ratio 1.75 or below) |
|---|---|---|
| Slide crop | Tall | Wide, without padding |
| Slide width | Full window width | Capped — see the note below |
| Slide height | Width times 1.25 | Two thirds of the space below the header |
| Brand header | None — the first slide carries the name | Pangea logo at 48 beside the wordmark |
| Headline | Above the artwork | Below the artwork |
| Fallback logo when an image fails | 128 | 256 |

One slide is always full-bleed across the carousel; slides never peek in from the edges, so a partly visible neighbour cannot be mistaken for content.

**The wide cap is still open.** The shipped value is 600. **840 is a suggestion, not a decision** — it appears in the [#7415](https://github.com/pangeachat/client/issues/7415) change list and is worth considering because it matches the point at which [`FluffyThemes`](../../lib/config/themes.dart) already treats a window as wide enough for side-by-side panes, so the screen would change character at the same width as the rest of the app.

What is settled is where the number should *not* come from. The narrower `MaxWidthBody` default in [layout.instructions.md](layout.instructions.md) is a reading measure, sized so a line of prose stays comfortable; a slide is artwork, so that reasoning does not carry over and the cap should not be aligned to it for consistency's sake.

Spacing below is in logical pixels. The three stacked gaps of 24 between carousel, dots and buttons are what keep the dots reading as a group with the carousel rather than with the buttons.

| Gap | Narrow | Wide |
|---|---|---|
| Around the carousel group — slides, headline and dots together | 32 above, 24 below | 32 above, 24 below |
| Above and below the brand header | — | 32 above, 24 below |
| Strip reserved for the headline above the artwork | 32 | — |
| Headline inset from the top of the slide | 16 | — |
| Headline side margins | 20 each side | — |
| Gap between artwork and headline | — | 24 |
| Carousel to dots | 24 | 24 |
| Dot size, and gap either side of each dot | 8, with 4 | 8, with 4 |
| Dots to buttons | 24 | 24 |
| Button column width | Capped at 300 | Capped at 300 |
| Button column side padding | 24 | 24 |
| Between the two buttons | 8 | 8 |
| Inside each button | 16 | 16 |

On wide windows the carousel takes twice the vertical space of the button area beneath it.

### Slide text

Each headline is localized text drawn over the artwork rather than baked into it, so it translates and scales independently of the image, and a copy change never means re-exporting six files.

**Placement differs by layout, and only by layout.** In the narrow layout the headline sits at the top of the slide, above the device mockup, so it is read before the image and stays clear of the buttons. In the wide layout it sits below the artwork, because the wide crop is close to full-bleed and has no clear space at its top edge. The tables above give the measurements for each.

| Property | Value |
|---|---|
| Typeface | Roboto |
| Weight | Semi-bold |
| Size | 24 |
| Alignment | Centred |
| Wrapping | Wraps to a second line rather than shrinking |

The same size and weight apply in both layouts. A headline that changes weight with window shape reads as a different voice for the same sentence, which is why the two layouts differ on position but not on type.

Colour and outline come from the scheme roles listed under Buttons, dots and colour, so the headline carries no brand value of its own. In the narrow layout the outline does the separating work over the map: because it takes the surface colour, it is near-white in light mode and near-dark in dark, which keeps the type punched out of the backdrop in both without needing a second rule.

**Size the reserved strip for two lines, not one.** Several supported languages run noticeably longer than English, and these headlines are already the longest strings on the screen, so a strip sized to one line of English will clip a translation rather than wrap it. Wrapping is the intended behaviour; shrinking the type to fit is not, because the size is doing legibility work over the artwork.

Text scaling should be capped rather than switched off. The strip cannot absorb unlimited growth, but disabling scaling outright fails the users who most need larger type. The current build disables it entirely — recorded in [issue #6294](https://github.com/pangeachat/client/issues/6294) — so treat that as the constraint to revisit, not as the intended design.

### Image assets

Slides are fetched at runtime from the bucket named in [`AppConfig`](../../lib/config/app_config.dart):

`https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com`

Files are named `Carousel_<number>_<crop>_<version>.png`. The number runs 1 to 6, the crop is `ratio4x5` for the narrow layout or `ratio2x1` for the wide one, and the version marks the design generation — currently `V5`. Twelve files make a full set.

The version suffix means a new set is added alongside the one it replaces rather than overwriting it, so the previous artwork stays retrievable if a slide has to be rolled back or compared. It also makes the files safe to cache forever, since a new generation never reuses an old name.

**Spell the crop and version tokens identically across a whole set.** Bucket keys are case-sensitive and the app builds each filename from one rule, so a set uploaded half as `_V5` and half as `_v5`, or half as `ratio2x1` and half as `ratio2x1_NoPadding`, cannot be addressed at all. The half that does not match the rule returns a not-found and falls back to the Pangea logo, which reads as a loading failure rather than a naming mistake.

`ratio2x1_NoPadding` is the legacy wide name. Its files are 16:9 despite what the token suggests, and they carry padding despite the name; the V5 wide files are a true 2:1. The client still composes that legacy name with no version token, so **it will switch from `ratio2x1_NoPadding` to `ratio2x1_V5`** — tracked as part of [#7415](https://github.com/pangeachat/client/issues/7415) and completing with it. Until then the files linked under Slide inventory are live in the bucket but unused by the app.

**Upload both crops of a slide together.** The app chooses a crop from the window shape, so replacing only one leaves the other layout on older artwork. Nothing fails visibly when this happens; the two layouts simply drift apart, and the gap is only found by opening the app at a different window shape.

### Slide inventory

A slide is two things kept in separate places: **artwork in the bucket, headline in the code.** Carousel slides are images uploaded to AWS S3. A headline is a localized string, so changing one means a code edit, retranslation into every supported language, and a release. Reword a headline only when the wording is worth that; restyle or redraw freely.

| # | Headline in code today | V5 headline | V5 artwork |
|---|---|---|---|
| 1 | Learn a language while texting your friends! | none — carried in the artwork | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_1_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_1_ratio2x1_V5.png) |
| 2 | Write and speak worry-free with Pangea Bot anytime, anywhere! | Explore, play and learn | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_2_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_2_ratio2x1_V5.png) |
| 3 | Join international learning communities, or start your own! | Conversation from Day One | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_3_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_3_ratio2x1_V5.png) |
| 4 | Play conversation games with the bot, classmates, and new friends! | Built for connection | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_4_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_4_ratio2x1_V5.png) |
| 5 | Jump into conversation from Day One with AI writing tools! | AI when you need it | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_5_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_5_ratio2x1_V5.png) |
| 6 | Play practice games personalized to your vocabulary and grammar needs! | Practice tailored for you | [narrow](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_6_ratio4x5_V5.png) · [wide](https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/Carousel_6_ratio2x1_V5.png) |

The V5 set is 800 x 1000 narrow and 1200 x 600 wide. Both land at roughly twice their on-screen size, which is what keeps the product UI inside the artwork legible rather than soft — the complaint that opened [#7415](https://github.com/pangeachat/client/issues/7415).

Slide number in the filename is the position in this table, so artwork and headline stay paired by number alone. Reordering the carousel therefore means renaming files as well as reordering the strings — cheaper to change what a slide says than where it sits.

Two things the V5 column changes beyond wording. **Slide 1 has no headline at all** — it opens on the brand line set inside the artwork, so the layout must allow an empty headline rather than assume six. And **slides 3 and 4 swap subjects** against the current order, so the pairing above is the mapping to build to, not a rename of the existing strings. Both are copy and ordering changes rather than art changes, and both carry the release and translation cost described above.

For how a headline is set and how it behaves as the window changes, see Slide text and Layout and responsiveness.

Hosting the slides remotely rather than bundling them means the feature story can be refreshed without an app release — which matters because the slides show real product UI, and that UI keeps changing. The cost is a live dependency: a stale or unreachable bucket reaches every user at once, so a failed image falls back to the Pangea logo rather than a broken-image box.

## Buttons, dots and colour

Get started and Login to my account sit together beneath the carousel on every slide. New users are prioritised by visual weight rather than by hiding the login path, because a returning user who reinstalled should not have to reach the end of a pitch to find their way back in.

Colour comes from the Material 3 scheme built in [`FluffyThemes`](../../lib/config/themes.dart), which derives every role from a single seed — the purple in [`AppConfig`](../../lib/config/app_config.dart), stored as a setting so it can change. Use the scheme roles below rather than literal hex values: roles resolve correctly again when the seed changes and when the theme switches to dark.

| Element | Scheme role | Why |
|---|---|---|
| Get started | `primaryContainer` on `onPrimaryContainer` | Filled and highest contrast — the path most visitors should take |
| Login to my account | `surface` on `onSurface` | Present on every slide but quieter. Tinted rather than plain, because an untinted button on a pale map reads as a floating rectangle with no edge |
| Active dot | `primary` | Matches the brand accent so position is readable at a glance |
| Remaining dots | `outlineVariant` | Visible enough to count, quiet enough not to compete with the buttons |
| Headline | `onPrimaryContainer` | The darkest tone of the brand hue, so the type holds against the map without introducing a colour outside the scheme |
| Headline outline | `surface` | Tracks the background rather than a fixed white, so the outline still separates the type when the theme flips to dark |

Both buttons share the corner radius defined in `AppConfig`, so they read as one control group rather than two unrelated shapes. The dots are fully rounded and cross-fade between the two roles when the slide changes, so the transition is visible without being animated distraction.

## Design refer in Figma

[Signup and Login](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=14378-43729)

The comps cover the narrow layout only. The wide layout follows the rules in the tables above, which stand as its specification until a comp exists.

The headline in the comps is drawn in a lighter purple than the role chosen above. Where the two disagree, the role wins — it keeps the screen inside one derived palette, and it follows the theme into dark mode on its own.

The comps also rewrite the headlines — shorter on slides 2 to 6, and absent on slide 1. Those are the intended wording; the strings listed under Slide inventory are what the code says today.

## Choosing a method

Signup and login are separate destinations offering the same three methods: Apple, Google and email. Each creates a distinct Matrix account, which is why the method chosen the first time matters enough to remember.

[`SignupPageView`](../../lib/routes/home/signup/signup_view.dart) carries the terms-of-service indicator; [`LoginOptionsView`](../../lib/routes/home/login/login_options_view.dart) does not, because agreement is collected once at account creation.

When a previous method is known, both screens name it. Login dims the other two options to guide without removing them; signup goes further and links across to login, since someone who already has an account has usually landed on the wrong screen. Neither screen removes an option, because the stored hint can be wrong and a person may intend a different method.

---
applyTo: "lib/config/**"
description: "How the shared design tokens reach the Flutter client — the PangeaColors theme extension, the rule for static AppConfig colours, the fidelity scheme variant, and why the Material 3 seed is not a token."
---

# Design Tokens (client)

Roles, sync direction and contrast gates are owned by [design-tokens.instructions.md](../../../.github/.github/instructions/design-tokens.instructions.md). Read that first; this doc covers only what is specific to the client.

## How tokens arrive

Brand roles live on the [`PangeaColors`](../../lib/config/pangea_colors.dart) theme extension on `ThemeData`, not on members of `ColorScheme`, because the scheme follows a seed the learner can change and the extension does not.

Every role on the extension is a tone of one key colour, so its contrast against the Material surfaces follows from tone distance rather than a hand-checked hex: a 40-tone gap clears the 3:1 floor for non-text UI, a 50-tone gap clears 4.5:1 for text. A role names where a colour may go and which ink pairs with it. Gold has `gold` for text, `goldGraphic` for marks with a 3:1 floor (an earned star, a focus ring, a diff underline), `goldFixedDim` with `onGoldFixed` for the bright fill and `goldFixed` one step paler, `goldContainer` with `onGoldContainer` for washes, `goldHighlight` for a hovered gold mark, and `goldTrack` for the unfilled length of a ring painted over map tiles (dark in light, a mid gold in dark, so the ring's arc and the map both keep 3:1 against it). Progress bars are the one deliberate exception to the mark floor: their fill is the plain bright `goldFixedDim` on the neutral `surfaceContainerHighest` track, about 1.3:1 in light, chosen 2026-09-14 over an outlined fill that read as clutter; the exact count sits in the bar's tooltip or label. Warning and success have the same four each, from the orange and green keys: `warning`, `warningGraphic`, `warningFixedDim` with `onWarningFixed`, `warningContainer` with `onWarningContainer`, and likewise `success`, `successGraphic`, `successFixedDim` with `onSuccessFixed`, `successContainer` with `onSuccessContainer`. Warning is orange rather than the org doc's red because the red family lands on the same tones as Material's error, and a caution that looks like a failure is the wrong signal. Error has one role on the extension, `errorGraphic`, for marks that must read as red: the composer's correction underline and highlight, the writing-assistance ring, a wrong-answer tint. It is a tone of Material's own error palette, T50 in light and T60 in dark, because the scheme's dark `error` is a T80 pastel that reads as pink on an underline; error text and the icon beside it keep `colorScheme.error`.

**No colour lives in `AppConfig`.** The key colours a theme extension turns into roles are constants on the extension itself (`PangeaColors.goldKey`, `successKey`, `warningKey`, `joinableKey`), read nowhere else; a widget reads a role from the theme, never a key or a helper. Do not add a static colour to `AppConfig`, and do not add a key that no extension consumes.

**A fill is chosen by the shape it fills.** A flat pill or chip on a surface — an XP or vocab count, a download status, a reacted reaction, a selected feedback row — fills with `secondaryContainer` and inks with `onSecondaryContainer`. A round toolbar button — the practice modes, more, hint, the reading-assistance modes — fills with `primaryContainer` under `onPrimaryContainer`, and while pressed draws its icon in `ThemeData.lightTone` (the surface in light, its ink in dark), because the pressed fill is darkened toward black and its own ink no longer reads on it. `primaryContainer` is a vivid fill under the fidelity variant, never a quiet tint: a pill that lets its text inherit `onSurface` on it measures 3.7:1 in light and 2.5:1 in dark. Decided 2026-09-11 from a side-by-side of the two treatments.

## Why the seed is not a token

The client builds its Material 3 palette with `ColorScheme.fromSeed`, and the seed is read from `AppSettings.colorSchemeSeedInt`, a setting a learner can change in Settings → Style. A synced value can therefore only set the *default* seed; it can never describe what a given user sees. Anything that must hold a fixed brand value reads the theme extension instead, because that is the only layer a user preference does not move.

The seed is expanded with the `fidelity` scheme variant, which keeps the seed's chroma so primary reads as the brand purple; Flutter's default `tonalSpot` capped it at a pastel. Chosen 2026-09-11 from a side-by-side of the variants.

Generated theme files are never hand-edited. See the invariant in the org doc.

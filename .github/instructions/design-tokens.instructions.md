---
applyTo: "lib/config/**"
description: "How the shared design tokens reach the Flutter client — the PangeaColors theme extension, the rule for static AppConfig colours, the fidelity scheme variant, and why the Material 3 seed is not a token."
---

# Design Tokens (client)

Roles, sync direction and contrast gates are owned by [design-tokens.instructions.md](../../../.github/.github/instructions/design-tokens.instructions.md). Read that first; this doc covers only what is specific to the client.

## How tokens arrive

Brand roles live on the [`PangeaColors`](../../lib/config/pangea_colors.dart) theme extension on `ThemeData`, not on members of `ColorScheme`, because the scheme follows a seed the learner can change and the extension does not.

Every role on the extension is a tone of one key colour, so its contrast against the Material surfaces follows from tone distance rather than a hand-checked hex: a 40-tone gap clears the 3:1 floor for non-text UI, a 50-tone gap clears 4.5:1 for text. A role names where a colour may go and which ink pairs with it. Gold has four: `gold` for text, `goldGraphic` for marks with a 3:1 floor (an earned star, a focus ring, a progress fill), `goldFixedDim` with `onGoldFixed` for the bright fill, and `goldContainer` with `onGoldContainer` for washes. Warning has the same four from the orange key, `warning`, `warningGraphic`, `warningFixedDim` with `onWarningFixed`, and `warningContainer` with `onWarningContainer`; orange rather than the org doc's red because the red family lands on the same tones as Material's error, and a caution that looks like a failure is the wrong signal.

**Static colours in `AppConfig` are read only by theme extensions.** They are the key colours a theme extension turns into roles; a widget reads a role from the theme. The direct reads that remain, and the `goldByTheme` family of helpers that now shim to the extension, are being migrated to role names as their sites are touched. Do not add new direct reads, and do not add a static colour that no extension consumes.

## Why the seed is not a token

The client builds its Material 3 palette with `ColorScheme.fromSeed`, and the seed is read from `AppSettings.colorSchemeSeedInt`, a setting a learner can change in Settings → Style. A synced value can therefore only set the *default* seed; it can never describe what a given user sees. Anything that must hold a fixed brand value reads the theme extension instead, because that is the only layer a user preference does not move.

The seed is expanded with the `fidelity` scheme variant, which keeps the seed's chroma so primary reads as the brand purple; Flutter's default `tonalSpot` capped it at a pastel. Chosen 2026-09-11 from a side-by-side of the variants.

Generated theme files are never hand-edited. See the invariant in the org doc.

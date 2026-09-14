---
applyTo: "lib/config/**"
description: "How the shared design tokens reach the Flutter client — the two-tier primary as Material actually renders it, the gold role names, and why the Material 3 seed is not a token."
---

# Design Tokens (client)

Roles, sync direction and contrast gates are owned by [design-tokens.instructions.md](../../../.github/.github/instructions/design-tokens.instructions.md). Read that first; this doc covers only what is specific to the client.

## How tokens arrive

Brand roles belong on a `ThemeExtension` on `ThemeData`, not on members of `ColorScheme`, because `ColorScheme` is derived from a seed the learner can change and so cannot hold a fixed brand value.

**No such extension exists yet.** `themes.dart` builds `ColorScheme.fromSeed` and nothing more, and the brand constants in `app_config.dart` are maintained by hand against the role table in the shared doc. Until the generator lands, that table is the only thing keeping this surface aligned.

## Why the seed is not a token

The client builds its Material 3 palette with `ColorScheme.fromSeed`, and the seed is read from `AppSettings.colorSchemeSeedInt` — a setting a learner can change in Settings → Style. A synced value can therefore only set the *default* seed; it can never describe what a given user sees. Anything that must hold a fixed brand value reads the theme extension instead, because that is the only layer a user preference does not move.

## The two-tier primary in the client

The org table separates `brand-identity` `#8560E0` (never text, never under text) from the text-bearing brand `#5E3ACF`. The client meets that rule through Material rather than by swapping constants (measured in #8817): `fromSeed` remaps the seed through a tonal palette, so what actually renders as `primary` is `#65558F` in light and `#D0BDFE` in dark — filled-button labels measure 6.46:1 and 7.78:1, primary-as-text 6.14:1 and 10.97:1, all past the 4.5:1 AA floor. That is why `AppConfig.primaryColor` stays `#8560E0`: it is the seed and identity color, and text never renders in it. Do not "fix" the seed to the darker brand value — the surfaces it feeds already pass, and darkening the seed would shift the whole derived scheme.

The direct `AppConfig.primaryColor` uses that bypass the scheme (analytics lerps, the rating meter, map pin fills, chat underlines) are non-text UI at the 3:1 floor, which `#8560E0` clears at 4.42:1 on white. A new use that puts text on or in the brand purple takes the scheme's `primary`/`onPrimary` (or the org table's `brand`), never the raw seed.

Known and deliberate divergence: the client's rendered brand purple (`#65558F`, chroma-dropped by Material's `tonalSpot` variant) is more muted than the website's `#5E3ACF`. Closing that gap means passing an explicit `primary` to `fromSeed` or moving the brand roles onto the theme extension above — a design decision, not a defect (#8817).

## Gold

The gold roles, their theme pairs, and the ramp mappings are owned by the org table. The client's `AppConfig` names — `gold`, `goldLight`, `goldDeep`, `goldByTheme`, `goldMarkByTheme`, `xpTrackByTheme`, and the powerups set — *are* the role names: the Figma variables and the business token export align to them (pangeachat/business#158). Any value change here follows the org doc's cross-check rule.

Generated theme files are never hand-edited. See the invariant in the org doc.

---
applyTo: "lib/config/**"
description: "How the shared design tokens reach the Flutter client — where the brand roles will live, and why the Material 3 seed is not a token."
---

# Design Tokens (client)

Roles, sync direction and contrast gates are owned by [design-tokens.instructions.md](../../../.github/.github/instructions/design-tokens.instructions.md). Read that first; this doc covers only what is specific to the client.

## How tokens arrive

Brand roles belong on a `ThemeExtension` on `ThemeData`, not on members of `ColorScheme`, because `ColorScheme` is derived from a seed the learner can change and so cannot hold a fixed brand value.

**No such extension exists yet.** `themes.dart` builds `ColorScheme.fromSeed` and nothing more, and the brand constants in `app_config.dart` are maintained by hand against the role table in the shared doc. Until the generator lands, that table is the only thing keeping this surface aligned.

## Why the seed is not a token

The client builds its Material 3 palette with `ColorScheme.fromSeed`, and the seed is read from `AppSettings.colorSchemeSeedInt` — a setting a learner can change in Settings → Style. A synced value can therefore only set the *default* seed; it can never describe what a given user sees. Anything that must hold a fixed brand value reads the theme extension instead, because that is the only layer a user preference does not move.

Generated theme files are never hand-edited. See the invariant in the org doc.

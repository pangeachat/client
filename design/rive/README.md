# Rive design sources

Editor sources for the Rive animations used in the app. Nothing here is bundled: `design/` is outside the asset paths declared in `pubspec.yaml`, so these files stay out of the shipped binary. The runtime `.riv` that the app actually loads lives in `assets/pangea/bot_faces/`.

## pangea_bot

The bot face. Authored by Matthew Haar, who built the original in 2024 and revised it in September 2026.

| File | What it is |
| --- | --- |
| `pangea_bot.rev` | Editor backup. This is the only editable source. Drag it into the Rive editor to open it. |
| `pangea_bot.riv` | Runtime export of that source, with data binding. Not yet wired into the app. |

A compiled `.riv` cannot be reopened in the editor, so the `.rev` is the file that matters. The original was commissioned without one, which left the animation uneditable for two years. Keep the `.rev` in step with any future export.

### Why this export is not the live asset yet

The live asset is still the 2024 export, driven through a state machine number input. This revision replaces that input with a view model, so swapping the file without updating the widget would leave every bot face stuck in one expression.

`BotIconViewModel` exposes:

| Property | Type | Notes |
| --- | --- | --- |
| `botColor` | color | Body colour. Shading follows it automatically. Default `#8B6AE2`. |
| `backgroundColor` | color | Backdrop. Default `#FFFFFF`. |
| `idle` | trigger | Returns any animation to idle. |
| `goldEmote` | trigger | Holds until `idle` fires. |
| `nonGoldEmote` | trigger | Holds until `idle` fires. |
| `surprised` | trigger | Holds until `idle` fires. |
| `addled` | trigger | Holds until `idle` fires. |
| `exit` | trigger | Plays the exit animation. Reachable only from idle. |

The artboard is `BotIconArtboard` and the state machine the app should select is `BotIconStateMachine`. The file also carries a second state machine, `DemoMachine`, which is the author's test harness and is not for app use.

Shading is built from Hard Light blend modes at full opacity rather than partial-opacity overlays, which is what lets one colour variable drive the whole body. Verified through rive 0.14.5: every bound hue produces the same two shade ratios, 0.75 and 0.53 of the base.

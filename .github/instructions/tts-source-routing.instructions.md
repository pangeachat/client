---
applyTo: "lib/pangea/text_to_speech/**,lib/pangea/common/widgets/word_audio_button.dart"
description: "How word-level TTS picks device vs backend audio — quality-driven on native, prefer-backend on web, Pro-gated, no per-language quality matrix."
---

# TTS Source Routing — Device vs Backend

Decides, per pronunciation request, whether word/token audio plays from **device TTS** (`flutter_tts`, free, offline) or **backend TTS** (`POST /choreo/text_to_speech`, Google Cloud neural/WaveNet, paid). Owned by [`TtsController`](../../lib/pangea/text_to_speech/tts_controller.dart); triggered from [`word_audio_button.dart`](../../lib/pangea/common/widgets/word_audio_button.dart). The backend handler and its own quality tiers are documented in the choreographer's [tts.instructions.md](../../../2-step-choreographer/.github/instructions/tts.instructions.md).

## The problem this solves

Device TTS quality varies wildly by language **and** by platform, and the worst cases are invisible to us. A German (L2) word read by desktop Chrome's voice has no German accent — the complaint that motivated this doc ([#6871](https://github.com/pangeachat/client/issues/6871), from an instructor evaluating a German pilot on Chrome). Routing such cases to backend Google TTS fixes pronunciation; routing everything to backend wastes cost/latency where the device is already good.

## What signal each surface gives us

This is the crux, and it's why a single rule can't cover every surface:

| Surface | Engine actually used | Per-voice quality signal available? |
|---|---|---|
| Native iOS / Android app | Apple / Android system TTS | **Yes** — `flutter_tts` `getVoices` returns a `quality` field (iOS `default`/`enhanced`/`premium`; Android `very-low`…`very-high`) |
| Safari (web) | Apple system voices, default tier only (Siri/premium voices not exposed to the web layer) | **No** — Web Speech API exposes no quality field |
| Chrome on Android (web) | Android system TTS | **No** — returns an unfiltered language list, not per-voice quality |
| Chrome desktop (web) | Google network voices + OS voices | **No** — and unmappable to any native assumption |

Two consequences drive the design:

- **Browser ≠ its native cousin for quality.** "Safari ≈ iOS" and "Chrome ≈ Android" hold only for *which languages exist*, not quality: Safari serves the downgraded default tier, and desktop Chrome uses its own voices entirely. So we cannot infer web quality from native behavior.
- **Web gives us nothing to measure.** The only place we get a real quality reading is the native app.

## Routing decisions

1. **Phoneme override → always backend.** When a `tts_phoneme` is resolved (heteronym disambiguation via the PT v2 cache), device TTS can't honor it, so the request goes to backend regardless of everything below. (Pre-existing behavior.)

2. **Language unsupported by device → backend.** If the device has no voice for the L2, backend is the only option. (Pre-existing.)

3. **Native, device voice is poor → backend.** On iOS/Android, read the `quality` of the best installed voice for the L2 and route to backend when it's below threshold (iOS below `enhanced`; Android below `high`). This is the new lever and the only fully accurate one — it sends a user with great on-device German straight to the fast local voice, and a user with a flat one to Google. **Adjusting the threshold here changes how aggressively we spend backend calls.**

4. **Web → prefer backend.** Web surfaces expose no quality signal and are reliably the weak ones (Safari's default tier, desktop Chrome's own voices). So for web, prefer backend rather than guess. This covers the original Chrome complaint without any per-language list.

5. **Otherwise → device.** Native with a good-quality voice and no phoneme stays local: free, instant, offline-capable.

### Why no per-language quality matrix

A predicted "language × platform" quality table was considered and rejected: native already gives a *real* runtime signal (no need to predict), and web quality depends on which voices the user has downloaded plus network state (impossible to predict, stale the day Apple/Google ship new voices). The native `quality` field plus "web prefers backend" covers the same ground without a table to maintain. **Do not reintroduce a hardcoded per-language device-quality list** unless a concrete case proves the two signals above insufficient.

## Pro gating

Backend TTS is entitlement-gated server-side (`has_active_entitlement` → 401 for free users), so routing must respect subscription state via [`SubscriptionController.isSubscribed`](../../lib/pangea/subscription/controllers/subscription_controller.dart):

- **Subscribed:** routing decisions above apply in full.
- **Not subscribed:** backend is unavailable, so device TTS is always the fallback — including for poor-quality and web cases. This keeps audio working for free users rather than erroring silently; the trade-off is that free users still hear the weak device voice. Whether word-level pronunciation should become a free feature is a separate product call, not decided here.

Any user-facing control that forces backend audio is a **Pro feature**: show a "Pro Only" affordance and open subscription management on tap for unsubscribed users, consistent with other paid tools.

## Optional override setting

The automatic routing above is the default and needs no user action — important because the user who hits the bug (a teacher demoing a pilot) will never discover a toggle. A manual override MAY be added in learning settings as a **Pro-gated** control (e.g. *Pronunciation audio: Auto / High-quality / Device*, default **Auto**) for users who want to force device audio (offline, latency, data) or force backend. It is an override on top of the default routing, never the gate that decides whether the bug is fixed. A default-off setting is not an acceptable substitute for fixing the default, because it leaves the first-impression case broken.

## Future Work

- [#6871](https://github.com/pangeachat/client/issues/6871) — Route word-level TTS through backend for languages with poor device pronunciation (German)

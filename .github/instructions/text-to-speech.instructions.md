---
applyTo: "lib/pangea/text_to_speech/**,lib/pangea/common/widgets/word_audio_button.dart"
description: "Client word-level TTS feature — device vs backend audio sources, quality-driven routing, phoneme playback, audio caching, and Pro gating."
---

# Text-to-Speech (Client)

Word- and token-level pronunciation audio: the learner taps a word (word card, token overlay, vocab details) and hears it spoken. Owned by [`TtsController`](../../lib/pangea/text_to_speech/tts_controller.dart); triggered from [`word_audio_button.dart`](../../lib/pangea/common/widgets/word_audio_button.dart). Scope is isolated-word playback; whole-message audio uses the same controller but is not the focus here.

Two audio sources back the feature:

- **Device TTS** — `flutter_tts` (the OS/browser speech engine). Free, offline, instant, but quality varies wildly by language and platform.
- **Backend TTS** — `POST /choreo/text_to_speech`, Google Cloud neural/WaveNet voices. Consistent high quality, but paid and adds a network round-trip. Handler and its own voice-quality tiers: choreographer [tts.instructions.md](../../../2-step-choreographer/.github/instructions/tts.instructions.md).

The core design problem is **picking the source per request** so pronunciation is good without spending backend calls where the device is already fine.

## Source routing

### The signal each surface gives us

This is the crux, and it's why one rule can't cover every surface:

| Surface | Engine actually used | Per-voice quality signal available? |
|---|---|---|
| Native iOS / Android app | Apple / Android system TTS | **Yes** — `flutter_tts` `getVoices` returns a `quality` field (iOS `default`/`enhanced`/`premium`; Android `very-low`…`very-high`) |
| Safari (web) | Apple system voices, default tier only (Siri/premium voices not exposed to the web layer) | **No** — Web Speech API exposes no quality field |
| Chrome on Android (web) | Android system TTS | **No** — returns an unfiltered language list, not per-voice quality |
| Chrome desktop (web) | Google network voices + OS voices | **No** — and unmappable to any native assumption |

Two consequences drive the design:

- **Browser ≠ its native cousin for quality.** "Safari ≈ iOS" and "Chrome ≈ Android" hold only for *which languages exist*, not quality: Safari serves the downgraded default tier, and desktop Chrome uses its own voices entirely. So we cannot infer web quality from native behavior.
- **Web gives us nothing to measure.** The only place we get a real quality reading is the native app.

### Routing decisions

In priority order:

1. **Phoneme override → backend.** A resolved `tts_phoneme` (heteronym disambiguation) can't be honored by device TTS, so it always goes to backend. See [Phoneme playback](#phoneme-playback).
2. **Language unsupported by device → backend.** No device voice for the L2 leaves backend as the only option.
3. **Native, device voice is poor → backend.** On iOS/Android, read the `quality` of the best installed voice for the L2 and route to backend when it's below threshold (iOS below `enhanced`; Android below `high`). This is the only fully accurate lever — it sends a user with good on-device German to the fast local voice and a user with a flat one to Google. **Tuning this threshold changes how aggressively we spend backend calls.**
4. **Web → prefer backend.** Web exposes no quality signal and is the reliably-weak surface (Safari's default tier, desktop Chrome's own voices), so prefer backend rather than guess. This is the case that motivated the feature ([#6871](https://github.com/pangeachat/client/issues/6871): a German pilot, flat pronunciation on desktop Chrome).
5. **Otherwise → device.** Native with a good-quality voice and no phoneme stays local: free, instant, offline.

### Why no per-language quality matrix

A predicted "language × platform" quality table was considered and rejected: native already gives a *real* runtime signal (no need to predict), and web quality depends on which voices the user downloaded plus network state — impossible to predict and stale the day Apple/Google ship new voices. The native `quality` field plus "web prefers backend" covers the same ground without a table to maintain. **Do not reintroduce a hardcoded per-language device-quality list** unless a concrete case proves these two signals insufficient.

## Phoneme playback

Heteronyms (e.g. 还 → hái vs huán) get arbitrary pronunciation from device TTS because it has no context. The fix is to speak a specific phoneme. Responsibilities split cleanly:

- **Producing and disambiguating** the phoneme is owned by phonetic transcription — see [phonetic-transcription-v2-design.instructions.md](phonetic-transcription-v2-design.instructions.md). By the time playback runs, PT has already chosen at most one `tts_phoneme` for the word.
- **Speaking** it is this feature: a phoneme override forces the backend route (decision 1 above), because only backend TTS renders phonemes. The backend's SSML phoneme rendering is owned by the choreographer [tts.instructions.md](../../../2-step-choreographer/.github/instructions/tts.instructions.md). The client treats `tts_phoneme` as an opaque string — no per-language logic.

**Cache-only resolution.** At playback time the controller resolves the phoneme from the **local PT v2 cache**, never a blocking network call, because playback is latency-sensitive and the PT response was almost certainly already fetched to render the transcription overlay. A cache miss falls through to normal routing (device or plain backend) rather than blocking — acceptable because heteronyms are a small fraction of words, and the user still gets audio, just without guaranteed disambiguation.

## Audio caching

Backend audio is cached client-side in [`text_to_speech_repo.dart`](../../lib/pangea/text_to_speech/text_to_speech_repo.dart) (short TTL) so repeated taps on the same word don't re-hit the network or re-bill. This is what keeps "prefer backend on web" and the phoneme path affordable: word audio is short, user-initiated, and highly repeat-tapped. The backend additionally has its own CMS audio cache (choreographer doc).

## Pro gating

Backend TTS is entitlement-gated server-side (`has_active_entitlement` → 401 for free users), so routing respects subscription state via [`SubscriptionController.isSubscribed`](../../lib/pangea/subscription/controllers/subscription_controller.dart):

- **Subscribed:** routing decisions apply in full.
- **Not subscribed:** backend is unavailable, so device TTS is the fallback for *every* case — including poor-quality and web. This keeps audio working rather than erroring silently; the trade-off is free users still hear the weak device voice. Whether word-level pronunciation should be free is a separate product call, not decided here.

Any user-facing control that forces backend audio is a **Pro feature**: show a "Pro Only" affordance and open subscription management on tap for unsubscribed users, consistent with other paid tools.

## Optional override setting

Automatic routing is the default and needs no user action — important because the user who hits the bug (a teacher demoing a pilot) will never discover a toggle. A manual override MAY be added in learning settings as a **Pro-gated** control (e.g. *Pronunciation audio: Auto / High-quality / Device*, default **Auto**) for users who want to force device audio (offline, latency, data) or force backend. It is an override on top of the default routing, never the gate that decides whether the bug is fixed: a default-off setting is not an acceptable substitute for fixing the default, because it leaves the first-impression case broken.

## Future Work

- [#6871](https://github.com/pangeachat/client/issues/6871) — Route word-level TTS through backend for languages with poor device pronunciation (German)

---
applyTo: "lib/routes/chat/events/text_to_speech/**,lib/pangea/text_to_speech/**,lib/pangea/common/widgets/word_audio_button.dart"
description: "Client word-level TTS — Pro gate, known-good-voice gate (native quality field / client-side web name patterns) before backend fallback."
---

# Word-Level Text-to-Speech (Client)

Word- and token-level pronunciation audio: the learner taps a word (word card, token overlay, vocab details) and hears it spoken. Owned by [`TtsController`](../../lib/routes/chat/events/text_to_speech/tts_controller.dart); triggered from the audio affordance in [`phonetic_transcription_widget.dart`](../../lib/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart) and the vocab and choice surfaces. Scope is isolated word/token playback.

Every `TtsController.tryToSpeak` call declares a `TtsUseCase` (words / choices / incomingMessage) mapping it to a per-surface audio toggle in the Audio section of learning settings. When the toggle is off, nothing plays; explicit audio buttons (those passing a `targetID` + context) show `TtsDisabledPopup` pointing to settings.

Two audio sources back the feature:

- **Device TTS** — `flutter_tts` (the OS/browser speech engine). Free, offline, instant, but quality varies wildly by language and platform.
- **Backend TTS** — `POST /choreo/text_to_speech`, Google Cloud neural/WaveNet voices. Consistent high quality, but paid and adds a network round-trip. Handler and its own voice-quality tiers: choreographer [tts.instructions.md](https://github.com/pangeachat/2-step-choreographer/blob/main/.github/instructions/tts.instructions.md).

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
- **Only native gives a quality *field*.** On native we read quality directly; web exposes no quality field, so on web quality must be inferred from the voice name (see [Known-good voice](#known-good-voice)).

### Routing decisions

In priority order, for a request:

1. **Not subscribed → device.** Backend TTS is entitlement-gated server-side (`has_active_entitlement` → 401 for free users), so subscription is the first branch: an unsubscribed user always plays device TTS — using the best voice available per [Known-good voice](#known-good-voice) — read via [`SubscriptionController.isSubscribed`](../../lib/features/subscription/controllers/subscription_controller.dart). Audio keeps working rather than erroring; the trade-off is free users hear whatever the device offers. Whether word-level pronunciation should be free is a separate product question, not decided here. The decisions below apply to subscribed users.
2. **Phoneme override → backend.** A resolved `tts_phoneme` (heteronym disambiguation) can't be honored by device TTS. See [Phoneme playback](#phoneme-playback).
3. **No device voice for the L2 → backend.** Nothing local to play.
4. **Known-good device voice available → device (that voice); otherwise → backend.** Rather than route by platform, check whether the device actually offers a good voice for the L2 and use it, falling back to backend only when it doesn't. This minimizes backend spend and fixes poor pronunciation at the source. See [Known-good voice](#known-good-voice) for how "good" is determined per surface.

The gate in (4) is deliberately **check-first, backend-second**: the worst case is a good voice we failed to recognize, which sends the request to backend — extra cost, never bad audio.

### Known-good voice

What counts as "known-good" differs by surface because the quality signal does:

- **Native (iOS/Android):** use the `quality` field from `flutter_tts` `getVoices` (iOS `default`/`enhanced`/`premium`; Android `very-low`…`very-high`). A voice at/above threshold (iOS `enhanced`, Android `high`) is good. No server data needed — the signal is on-device. **Tuning the threshold changes how aggressively we spend backend calls.**
- **Web (Safari/Chrome):** the Web Speech API exposes no quality field, and flutter_tts on web surfaces only the voice `name` and locale — it drops `localService` and `voiceURI` — so the **name is the only signal available**. "Good" is therefore inferred from name patterns: `Google` (matches Chrome's network `Google Deutsch`-style voices), `Online (Natural)` (Edge neural), `(Enhanced)` / `(Premium)` (downloaded Apple voices), plus an exclusion list for specific bad voices. These patterns are **hardcoded in the client**, not server-fetched: they are broad vendor naming conventions (the `Google`, `(Enhanced)`, `Online (Natural)` markers have held across many browser/OS releases) rather than per-voice IDs, and the safe fallback means a wrong pattern costs a backend call, not bad audio — so remote tuning isn't worth the cross-repo machinery for v1. Lifting the set (or just the exclusion list) to CMS is a later option if a specific bad voice ever needs excluding without waiting for a client release. The good web voices are often network voices that load asynchronously, so the availability check must run after the voice list has loaded, not on the first call.

This is **not** the per-language quality matrix we rejected: it's a small, mostly language-agnostic set of name patterns, and the safe fallback (no match → backend) means a stale or incomplete set costs backend calls, never quality. Native needs no list at all.

When a known-good voice is found, the controller must **explicitly select it** on the utterance — setting only the language and letting the engine pick its default is what produces poor pronunciation even when a good voice is installed (e.g. on Chrome a flat default voice is chosen over the higher-quality `Google Deutsch`). Active voice selection is the primary fix; backend is the fallback only when no good voice exists.

**Validation:** the name patterns and thresholds are platform conventions, not guarantees, so they must be confirmed against real `getVoices` output per target browser/OS before relying on them.

### Failure handling

Choosing a source is half the job; either source can fail after it was chosen. A request must always end — with audio if any source can still give it, and with its play indicator cleared and its listening measurement closed either way.

- **Backend fails or is slow → device.** When the backend fetch fails or misses its deadline (one second when the device has a voice to fall back to; the full deadline for a phoneme request, since the device cannot render the phoneme — #8076), the device voice plays instead, if there is one.
- **Device fails → backend.** The mirror. A device utterance that never produced audio and was not stopped by the app — the engine reported an error before it started (`not-allowed`, `synthesis-failed`), never reported a start within a short watchdog window, or returned without ever starting — is rescued by backend TTS when the request may reach the backend at all and the user is subscribed. Setting-driven read-aloud (`allowChoreoPlay: false`) is never rescued; silence there is the design (see [message-read-aloud.instructions.md](message-read-aloud.instructions.md)). A stop is never rescued: the learner tapping stop, or a later tap superseding the word, asked for silence.
- **A device utterance always ends the request.** The plugin's `speak` future is not trusted to resolve — on the web it never does when the utterance errors, which is also how Chrome reports an interruption, and on iOS it never does when a later stop drops it. Each utterance is tracked instead (`TtsDeviceUtterance`) and settled by whichever comes first: the engine's completion, cancel or error callback, the speak future, or the start watchdog. One rule decides what the learner heard: audio was heard iff the engine reported a start; otherwise the utterance was cancelled if the app asked for the stop, and failed if nobody did. A word cut off by the next tap counts as heard for as long as it played (#8455).
- **The next word waits for the engine to confirm the stop.** Cutting off a word and issuing the next in the same instant loses the second on the web — the browser plugin drops a `speak` while it still believes the previous utterance is playing, and the browser confirms the cancel asynchronously. So `stop()` waits, briefly and bounded, for that confirmation before the next word is issued.

## Phoneme playback

Heteronyms (e.g. 还 → hái vs huán) get arbitrary pronunciation from device TTS because it has no context. The fix is to speak a specific phoneme. Responsibilities split cleanly:

- **Producing and disambiguating** the phoneme is owned by phonetic transcription — see [phonetic-transcription-v2-design.instructions.md](phonetic-transcription-v2-design.instructions.md). By the time playback runs, PT has already chosen at most one `tts_phoneme` for the word.
- **Speaking** it is this feature: a phoneme override forces the backend route (decision 2 above), because only backend TTS renders phonemes. The backend's SSML phoneme rendering is owned by the choreographer [tts.instructions.md](https://github.com/pangeachat/2-step-choreographer/blob/main/.github/instructions/tts.instructions.md). The client treats `tts_phoneme` as an opaque string — no per-language logic.

**Cache-only resolution.** At playback time the controller resolves the phoneme from the **local PT v2 cache**, never a blocking network call, because playback is latency-sensitive and the PT response was almost certainly already fetched to render the transcription overlay. A cache miss falls through to normal routing (device or plain backend) rather than blocking — acceptable because heteronyms are a small fraction of words, and the user still gets audio, just without guaranteed disambiguation.

## Audio caching

Backend audio is cached client-side in [`text_to_speech_repo.dart`](../../lib/routes/chat/events/text_to_speech/text_to_speech_repo.dart) (short TTL) so repeated taps on the same word don't re-hit the network or re-bill. This is what keeps the backend-fallback and phoneme paths affordable: word audio is short, user-initiated, and highly repeat-tapped. The backend additionally has its own CMS audio cache (choreographer doc).

## Optional override setting

Automatic routing (above) is the default and needs no user action; a setting the user must discover would leave the common case unaddressed. A manual override MAY be added in learning settings for users who want to force device audio (offline, latency, data) or force backend — e.g. *Pronunciation audio: Auto / High-quality / Device*, default **Auto**. It is an override on top of automatic routing, not a precondition for it.

Because forcing backend audio depends on backend TTS, such a control is a **Pro feature**: show a "Pro Only" affordance and open subscription management on tap for unsubscribed users, consistent with other paid tools.

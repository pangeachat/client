---
applyTo: "lib/routes/chat/events/text_to_speech/**"
description: "Automatic read-aloud of incoming L2 chat messages — the opt-in setting, what qualifies to be read, single-slot playback, and stop conditions."
---

# Message Read-Aloud (Client)

A boolean learning setting that controls auto-read-aloud for received messages.

Incoming messages in the learner's target language are spoken automatically, turning an ordinary chat into listening practice with nothing to tap. Pronunciation audio for a single tapped word is a separate feature — see [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md).

## The setting
Off by default, opt-in per learner: Automatically read aloud all received messages in learning settings, stored as autoReadAloudMessages on ToolSetting. Default off because unprompted audio in a messaging app is intrusive for anyone who didn't ask for it.

### Enabling requires a qualifying voice
Turning the toggle on first runs the same known-good-voice gate playback uses (see Audio source below), against the learner's selected L2. When no known-good voice exists, the toggle stays off and a popup explains how to get one where the learner currently is (#8113):

- **Desktop web, non-Chromium** (Safari, Firefox): try Chrome or Edge. These browsers bundle their own high-quality voices; Safari exposes only plain-named compact system voices to the Web Speech API, so no Safari voice can ever pass the gate.
- **Mobile web, any browser**: use the mobile app. Every iOS browser is WebKit underneath and shares Safari's voices, so recommending another browser there would not help.
- **iOS app**: download an Enhanced/Premium voice for the L2 (Settings → Accessibility → Spoken Content → Voices). iOS offers no public deep link to that screen — the private `App-Prefs:` scheme risks App Store rejection — so the popup opens the Settings app and lists the path, like the autocorrect dialog.
- **Android app**: fire the system voice-data install intent (`android.speech.tts.engine.INSTALL_TTS_DATA`), falling back to the TTS settings screen. Rare in practice; Google TTS usually passes the gate.

The advice hedges ("usually") rather than promises: the gate is per-language, and for a low-resource L2 even Chrome or Edge may lack a qualifying voice.

The check is device-level while the setting is account-level. Enabling on a platform with a good voice does not make other platforms play; the silence rule under Audio source still governs playback everywhere. Silence remains correct at playback time — but at the moment of decision the learner deserves to know why nothing would play and what to change; silently doing nothing at toggle time read as broken (#7436).

## What gets read
A message is read only when all of these hold:

- It was received — the learner's own sent messages are not read.
- It is in the learner's L2 (target language). Messages in the L1 or an unknown language offer no listening practice.
- It arrived in the currently open chat, while that chat was open. Opening a chat reads nothing retroactively — a backlog of unheard messages would be noise rather than practice — and messages in background rooms have no visible counterpart on screen to follow along with.

## Audio source
Device text-to-speech only; this flow never calls the choreographer. Backend TTS is paid per request, and unlike a deliberate word tap this fires on every eligible incoming message, so the volume is unbounded and driven by how much other people type rather than by the learner.

The known-good-voice gate in [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md) applies unchanged. When the device offers no known-good voice for the L2, nothing is read at all. Silence is the intended outcome here rather than a reason to fall back to the backend, because poor pronunciation teaches the wrong thing.

## One message at a time
Playback holds a single waiting slot: while a message is being read, at most one message waits, and a newer arrival replaces whichever message was waiting. The learner stays at most one message behind the conversation, so what they hear is still on screen. Reading every message in order would fall progressively further behind; ignoring everything that arrives mid-playback would instead skip the newest messages and drift the audio away from where the learner is looking.

Read-aloud shares the single TtsController with word-level playback, so only one utterance plays anywhere in the app — tapping a word interrupts read-aloud.

## When it stops
- The chat closes or loses focus. Audio stops immediately.
- A message is selected. Read-aloud does not start while a message is selected, and selecting one stops playback in progress. The selected message has the learner's attention and its own audio controls.
- The learner starts drafting. Playback stops and any waiting message is dropped rather than held for later. Read-aloud stays suppressed while the input bar holds text, resuming once the draft is sent or cleared — composing a reply is the moment an interruption costs the most.
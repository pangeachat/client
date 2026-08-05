---
applyTo: "lib/routes/chat/events/text_to_speech/**"
description: "Automatic read-aloud of incoming L2 chat messages — the opt-in setting, what qualifies to be read, single-slot playback, and stop conditions."
---

# Message Read-Aloud (Client)

A boolean learning setting that controls auto-read-aloud for received messages.

Incoming messages in the learner's target language are spoken automatically, turning an ordinary chat into listening practice with nothing to tap. Pronunciation audio for a single tapped word is a separate feature — see [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md).

Two independent switches turn it on: the always-on setting below, and [Voice mode](#voice-mode). They differ in what they read and in whether they may spend backend TTS, so treat them separately — `qualifies()` and `useBackendTts()` are the pure predicates that encode the difference.

## The setting
Off by default, opt-in per learner: the **Incoming messages** toggle in the Audio section of learning settings, stored as `audioIncomingMessages` (`ToolSetting.audioIncomingMessages`). Default off because unprompted audio in a messaging app is intrusive for anyone who didn't ask for it. Changing the target language never flips this toggle — the opt-in rationale is language-independent, unlike the words/choices audio toggles which reset to on.

## Voice mode
A learner who sends a voice message is in a spoken exchange, so the bot's reply to it may reach backend TTS rather than staying silent when the device has no known-good voice. This is what remains of the rule the **bot** used to apply server-side: it answered a voice note with generated audio, and the client auto-played it. The bot no longer generates TTS at all.

- **Trigger.** `MessageReadAloudController.voiceMode`, set by the chat controller after a voice message sends successfully, cleared when the learner sends text (hooked at the send, so activity buttons and suggestion chips end it too, and it stops playback in progress rather than only blocking the next one).
- **Session state, not derived.** A predicate over `Timeline.events` would misfire three ways: errored events are pinned to the front of that list, so a failed upload would hold the mode open; edits are themselves `m.room.message` events in it, so editing an old message would flip it; and pagination can page in a week-old voice note. Read-aloud only reads messages arriving after the chat opens, so session state covers exactly the same cases.
- **Outside the toggle, not a second toggle.** A voice reply is read whether or not `audioIncomingMessages` is on, via the ungated `TtsUseCase.voiceReply`. The toggle governs *unprompted* audio — messages arriving unbidden while the chat is open — and a reply to something the learner just said out loud is not unprompted. Gating it there would mean a voice message gets a silent answer by default, where the bot previously spoke it automatically. No setting is added: the count of toggles in learning settings is unchanged.
- **Backend allowed.** Voice replies are the one read-aloud path that may reach paid TTS, because device-only would mean total silence — no error, no indicator — wherever the device has no known-good L2 voice. Still cheaper than what it replaces: the bot bought a paid request for *every* voice reply, whereas this routes device-first and is bounded by the learner's own voice messages.
- **Bot only.** The backend-TTS exception applies to the bot's reply alone, so a busy activity room cannot turn every participant's message into a paid request.

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
Device text-to-speech only for setting-driven reads; that flow never calls the choreographer. Backend TTS is paid per request, and unlike a deliberate word tap this fires on every eligible incoming message, so the volume is unbounded and driven by how much other people type rather than by the learner.

The known-good-voice gate in [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md) applies unchanged. When the device offers no known-good voice for the L2, nothing is read at all. Silence is the intended outcome here rather than a reason to fall back to the backend, because poor pronunciation teaches the wrong thing.

**Voice-mode replies are the one exception** (`useBackendTts()`): they take the normal device-first routing and fall back to backend when the device has no known-good voice. Two reasons the rule above does not apply. Their volume is bounded by the learner's own voice messages — the bound the setting-driven case lacks — and silence is not an acceptable outcome here: the bot used to guarantee an audible reply on every device, so device-only would break the spoken exchange, with no error and no indicator, on Safari, on desktop Chrome without a Google voice, and on Android without a high-quality voice.

## One message at a time
Playback holds a single waiting slot: while a message is being read, at most one message waits, and a newer arrival replaces whichever message was waiting. The learner stays at most one message behind the conversation, so what they hear is still on screen. Reading every message in order would fall progressively further behind; ignoring everything that arrives mid-playback would instead skip the newest messages and drift the audio away from where the learner is looking.

Read-aloud shares the single TtsController with word-level playback, so only one utterance plays anywhere in the app — tapping a word interrupts read-aloud.

## When it stops
- The chat closes or loses focus. Audio stops immediately.
- A message is selected. Read-aloud does not start while a message is selected, and selecting one stops playback in progress. The selected message has the learner's attention and its own audio controls.
- The learner starts drafting. Playback stops and any waiting message is dropped rather than held for later. Read-aloud stays suppressed while the input bar holds text, resuming once the draft is sent or cleared — composing a reply is the moment an interruption costs the most.
- The learner is recording a voice message. Recording is inline rather than modal, so none of the conditions above catch it, and in voice mode the learner is recording by construction. Without this, playback would go out loud into a hot mic, be captured by the recorder and uploaded to speech-to-text.
- The learner sends text, which additionally ends [Voice mode](#voice-mode) itself.
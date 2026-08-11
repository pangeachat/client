---
applyTo: "lib/routes/chat/events/text_to_speech/**"
description: "Read-aloud of L2 chat messages — the two settings (on new message, on click), what qualifies to be read, single-slot playback, and stop conditions."
---

# Message Read-Aloud (Client)

Two boolean learning settings that control read-aloud for chat messages: one for messages as they arrive, one for a message the learner clicks.

Incoming messages in the learner's target language are spoken automatically, turning an ordinary chat into listening practice with nothing to tap. Pronunciation audio for a single tapped word is a separate feature — see [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md).

Two independent switches turn the automatic reads on: the new-message setting below, and [Voice mode](#voice-mode). They differ in what they read and in whether they may spend backend TTS, so treat them separately — `qualifies()` and `useBackendTts()` are the pure predicates that encode the difference.

## The settings
Two toggles in the Audio section of learning settings, both **on by default** (#8264):

- **On new message** — automatic read-aloud of received messages as they arrive, stored as `audioOnNewMessage` (`ToolSetting.audioOnNewMessage`).
- **On message click** — read-aloud of a message the learner clicks, stored as `audioOnMessageClick` (`ToolSetting.audioOnMessageClick`).

They replaced the single opt-in, default-off **Incoming messages** toggle (`audioIncomingMessages`), which gated both triggers. #8264 reversed the default and split the triggers so each can be turned off alone. The retired key deliberately does not seed the new toggles: it was default-off, so a stored false is almost always the old default rather than a choice, and the point of the change is that everyone starts on. Changing the target language never flips these toggles.

## Voice mode
A learner who sends a voice message is in a spoken exchange, so the bot's reply to it may reach backend TTS rather than staying silent when the device has no known-good voice. This is what remains of the rule the **bot** used to apply server-side: it answered a voice note with generated audio, and the client auto-played it. The bot no longer generates TTS at all.

- **Trigger.** `MessageReadAloudController.voiceMode`, set by the chat controller after a voice message sends successfully, cleared when the learner sends text (hooked at the send, so activity buttons and suggestion chips end it too, and it stops playback in progress rather than only blocking the next one).
- **Session state, not derived.** A predicate over `Timeline.events` would misfire three ways: errored events are pinned to the front of that list, so a failed upload would hold the mode open; edits are themselves `m.room.message` events in it, so editing an old message would flip it; and pagination can page in a week-old voice note. Read-aloud only reads messages arriving after the chat opens, so session state covers exactly the same cases.
- **Outside the toggle, not a second toggle.** A voice reply is read whether or not `audioOnNewMessage` is on, via the ungated `TtsUseCase.voiceReply`. The toggle governs *unprompted* audio — messages arriving unbidden while the chat is open — and a reply to something the learner just said out loud is not unprompted. Gating it there would mean a voice message with the toggle off gets a silent answer, where the bot previously spoke it automatically. No setting is added for voice mode itself.
- **Backend allowed.** Voice replies are the one read-aloud path that may reach paid TTS, because device-only would mean total silence — no error, no indicator — wherever the device has no known-good L2 voice. Still cheaper than what it replaces: the bot bought a paid request for *every* voice reply, whereas this routes device-first and is bounded by the learner's own voice messages.
- **Bot only.** The backend-TTS exception applies to the bot's reply alone, so a busy activity room cannot turn every participant's message into a paid request.

### Enabling requires a qualifying voice
Turning either message-audio toggle on first runs the same known-good-voice gate playback uses (see Audio source below), against the learner's selected L2. When no known-good voice exists, the toggle stays off and a popup explains how to get one where the learner currently is (#8113):

- **Desktop web, non-Chromium** (Safari, Firefox): try Chrome or Edge. These browsers bundle their own high-quality voices; Safari exposes only plain-named compact system voices to the Web Speech API, so no Safari voice can ever pass the gate.
- **Mobile web, any browser**: use the mobile app. Every iOS browser is WebKit underneath and shares Safari's voices, so recommending another browser there would not help.
- **iOS app**: download an Enhanced/Premium voice for the L2 (Settings → Accessibility → Spoken Content → Voices). iOS offers no public deep link to that screen — the private `App-Prefs:` scheme risks App Store rejection — so the popup opens the Settings app and lists the path, like the autocorrect dialog.
- **Android app**: fire the system voice-data install intent (`android.speech.tts.engine.INSTALL_TTS_DATA`), falling back to the TTS settings screen. Rare in practice; Google TTS usually passes the gate.

The advice hedges ("usually") rather than promises: the gate is per-language, and for a low-resource L2 even Chrome or Edge may lack a qualifying voice.

The check is device-level while the setting is account-level. Enabling on a platform with a good voice does not make other platforms play; the silence rule under Audio source still governs playback everywhere. Silence remains correct at playback time — but at the moment of decision the learner deserves to know why nothing would play and what to change; silently doing nothing at toggle time read as broken (#7436).

## What gets read
A message is read on arrival (the **On new message** toggle) only when all of these hold:

- It was received — the learner's own sent messages are not read unprompted.
- It is in the learner's L2 (target language). Messages in the L1 or an unknown language offer no listening practice.
- It arrived in the currently open chat, while that chat was open. Opening a chat reads nothing retroactively — a backlog of unheard messages would be noise rather than practice — and messages in background rooms have no visible counterpart on screen to follow along with.

## Reading on click
Tapping a message is a deliberate request to engage with it, so it speaks that message, behind the **On message click** toggle. Same qualifying conditions, same device-only source as an arriving message — only the trigger and the gate differ.

- **Same conditions as an arriving message** (in the L2, text, synced, not redacted), minus the arrived-while-open rule. That rule exists to stop a backlog of unheard messages playing at once; a message the learner picked out and tapped is by definition on screen and asked for.
- **Own messages included** (#8264). The received-only rule is about unprompted audio; a click asks to hear that message, whoever sent it, and hearing your own L2 sentence back is pronunciation feedback on something you produced.
- **Gated on its own toggle**, independent of the new-message one, so a learner can keep tap-to-hear while silencing the ambient reads, or the reverse.
- **Device only**, through the same known-good-voice gate — silence when the device has no good L2 voice. Voice mode's backend exception does not extend here; a tap is not a spoken exchange.
- **Not when a token was tapped.** Tapping a word selects that token and plays the word. The more specific request wins, and the two would otherwise talk over each other.
- **Not when the tutorial opens the toolbar.** The reading-assistance tutorial selects a message on the learner's behalf and speaks its own instruction over it. Tutorial-driven selections are marked at the call site rather than inferred from how the toolbar was opened.
- **Chat only.** The example-message toolbar on analytics detail pages is a reference lookup, not a message in a conversation.

## Audio source
Device text-to-speech only for setting-driven reads; that flow never calls the choreographer. Backend TTS is paid per request, and unlike a deliberate word tap this fires on every eligible incoming message, so the volume is unbounded and driven by how much other people type rather than by the learner.

The known-good-voice gate in [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md) applies unchanged. When the device offers no known-good voice for the L2, nothing is read at all. Silence is the intended outcome here rather than a reason to fall back to the backend, because poor pronunciation teaches the wrong thing.

**Voice-mode replies are the one exception** (`useBackendTts()`): they take the normal device-first routing and fall back to backend when the device has no known-good voice. Two reasons the rule above does not apply. Their volume is bounded by the learner's own voice messages — the bound the setting-driven case lacks — and silence is not an acceptable outcome here: the bot used to guarantee an audible reply on every device, so device-only would break the spoken exchange, with no error and no indicator, on Safari, on desktop Chrome without a Google voice, and on Android without a high-quality voice.

## One message at a time
Playback holds a single waiting slot: while a message is being read, at most one message waits, and a newer arrival replaces whichever message was waiting. The learner stays at most one message behind the conversation, so what they hear is still on screen. Reading every message in order would fall progressively further behind; ignoring everything that arrives mid-playback would instead skip the newest messages and drift the audio away from where the learner is looking.

Read-aloud shares the single TtsController with word-level playback, so only one utterance plays anywhere in the app — tapping a word interrupts read-aloud, and the toolbar's sentence-audio button stops it before starting its own.

## When it stops
- The chat closes or loses focus. Audio stops immediately.
- A message is selected. Automatic read-aloud does not start while a message is selected, and selecting one stops playback in progress and drops the waiting message — the conversation has moved past what the learner is now looking at. Selection may then speak the *selected* message instead, see [Reading on click](#reading-on-click).
- The learner starts drafting. Playback stops and any waiting message is dropped rather than held for later. Read-aloud stays suppressed while the input bar holds text, resuming once the draft is sent or cleared — composing a reply is the moment an interruption costs the most.
- The learner is recording a voice message. Recording is inline rather than modal, so none of the conditions above catch it, and in voice mode the learner is recording by construction. Without this, playback would go out loud into a hot mic, be captured by the recorder and uploaded to speech-to-text.
- The learner sends text, which additionally ends [Voice mode](#voice-mode) itself.
---
applyTo: "lib/routes/chat/events/text_to_speech/**"
description: "Automatic read-aloud of incoming L2 chat messages — the opt-in setting, what qualifies to be read, single-slot playback, and stop conditions."
---

# Message Read-Aloud (Client)

A boolean learning setting that controls auto-read-aloud for received messages.

Incoming messages in the learner's target language are spoken automatically, turning an ordinary chat into listening practice with nothing to tap. Pronunciation audio for a single tapped word is a separate feature — see [word-text-to-speech.instructions.md](word-text-to-speech.instructions.md).

## The setting
Off by default, opt-in per learner: the **Incoming messages** toggle in the Audio section of learning settings, stored as `audioIncomingMessages` (`ToolSetting.audioIncomingMessages`). Default off because unprompted audio in a messaging app is intrusive for anyone who didn't ask for it. Changing the target language never flips this toggle — the opt-in rationale is language-independent, unlike the words/choices audio toggles which reset to on.

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
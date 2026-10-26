---
description: "What the client decides about 1:1 calls: ringing, ending, recording, and who reads the transcript."
applyTo: "lib/routes/chat/calls/**,pangea_packages/pangea_call_capture/**,lib/widgets/matrix.dart,ios/Runner/Info.plist,pubspec.yaml,lib/utils/background_push.dart,lib/utils/push_helper.dart"
---

# Voice & Video Calls — Client

## Purpose

Two learners in a direct chat can talk by voice or video, and each person's speech counts toward their own learning. The [org doc](../../../.github/.github/instructions/voice-video-calls.instructions.md) owns why calls exist, rollout, analytics, consent and pricing; [call-device-ownership](call-device-ownership.instructions.md) owns two devices in one call.

## The experience

1. The call button is greyed until the other person has joined the chat.
2. A call rings the other person's devices, even a locked phone; unanswered, it becomes "Missed call".
3. Before recording, the call says it is transcribed and saved, and both people can read it.
4. Leaving the chat mid-call keeps the call, as a floating tile.
5. Afterwards the chat shows one card and a transcript that reads like the chat.

## Decisions

Decision; reason. Who re-decides is unassigned throughout.

### The call

- The call belongs to the app, not a screen: leaving the chat never hangs up, and messaging carries on.
- Call media is not end-to-end encrypted: our chats are unencrypted, and the standard then forbids it.
- Our Matrix library stays pinned, moved only for a named fix: calls rely on parts with no stable contract.
- Calling needs both people joined; otherwise it rings nobody.
- A microphone that will not open is no call; anything else degrades.

### Ending and coming back

- Pressing end ends it for both; only someone who vanished gets a grace window.
- Declined or unanswered is told apart from failed: the caller is owed the reason.
- Leaving the chat ends the call; a call cannot outlive its chat.
- A ring during a call is declined as busy, unless both people called each other at once.
- A crashed device may offer to rejoin for about ninety seconds; declining ends the call.
- Both people see the same call clock.

- One card per call when either side survived, worded the same in the chat list; a call both people reloaded out of leaves none ([.github#410](https://github.com/pangeachat/.github/issues/410)).
- Talk time (card, analytics) excludes stretches nobody could hear; the on-screen length does not.

### Recording

- Each device records only its own speaker, after echo cancellation, so nobody is credited with another's voice.
- Nothing is recorded while ringing, while the other person is gone or offline, or while muted.
- One device per account records, so speech never counts twice.
- Silence is not transcribed; providers invent words for it ([call-silence-trim-design](call-silence-trim-design.instructions.md)).
- The notice says what happens to the words: that makes recording the other speaker legitimate.
- Call audio, never video, is saved like a voice message, with the same retention.
- A whole-call recording is shown only when every piece is accounted for.

### The transcript

- The saved recording is transcribed after the call, live transcription is the fallback, and each side succeeds or fails alone.
- Transcription is paid: a subscriber's app also fills in the other person's side. With no subscriber nothing is transcribed, though audio is kept; others see a locked placeholder.
- Each side uses its speaker's target language, fixed at call start.
- Only the two chat members get a section, so a forged card cannot add a speaker.
- Sides merge on the call server's clock, so a wrong phone clock never changes who spoke first.
- A side that cannot be ordered shows each speaker separately. Pauses are not drawn.

### Three states, and the distinction that is not one

- "They said nothing", "their words are missing" and "we stopped reading early" stay three answers; collapsing them is how a transcript lies. Silence is a complete record, and our own failures are named as ours.
- A turn's time is shown only as precisely as measured ("m:ss", "by m:ss", or none).

### Ringing when the app is closed

- A closed phone rings only when an open app would, for ninety seconds at most.
- On iOS the system call screen is the ring; the microphone is asked for before the first ring.
- Android asks for notifications, then for full-screen calls, each when a call needs it.
- No permission ask interrupts a call.
- On the web only open tabs ring.

## Open questions

- Should a device with no microphone get a listen-only call?
- History records a busy decline as "Call declined", not "busy". Intended?
- The old doc said the missed-call push stops a closed phone ringing; the code stops it by watching the caller. Which?
- Recording-based turns still drop punctuation, yet [#9303](https://github.com/pangeachat/client/issues/9303) is closed. Accepted?
- The old doc called live-fallback chunks short; they run 45 to 90 seconds. Short enough?

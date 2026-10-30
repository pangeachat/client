---
description: "What happens when two of a learner's devices are in the same call: both go silent, the learner picks one, the other leaves, and the call is credited once."
applyTo: "lib/routes/chat/calls/**"
---

# Two Devices, One Call — Client

A learner signed in on a phone and a laptop can end up in one call on both. The other person then hears them twice, and their analytics count the same speech twice. This doc decides how the app resolves that; [voice-video-calls.instructions.md](voice-video-calls.instructions.md) owns everything else about a call.

## The experience

1. The moment either device sees the other, both close the microphone and camera and keep them closed.
2. A moment later both say the call is open on two devices and nothing is being sent until the learner picks one: **Use this device** or **Leave the call here**. A minimized call opens full screen so the prompt is seen.
3. The device not chosen leaves, saying "This call is continuing on your other device."
4. The chosen device says nothing. Once the other has left, the call resumes with the microphone, camera and view as the learner had them.
5. If the other device runs an older version that cannot leave on its own, this device says so and offers only **Leave the call here**.
6. If nobody chooses, each device leaves after a short wait and the call ends.
7. The other person hears silence and sees the learner as muted, never as gone.

## Decisions

- **Notice, do not prevent.** When both devices answer at once neither can see the other, so nothing can stop the second joining. Unassigned.
- **The learner chooses; the app never picks.** Every computed rule failed somewhere; the learner cannot pick wrong. Unassigned.
- **Silence first, prompt a moment later.** Muting is cheap and undoable and is what limits doubled audio; interrupting the conversation is not. The ordinary mute and camera buttons cannot reopen a held device, or the prompt's promise breaks. Unassigned.
- **Act only on what was seen.** "Not arrived yet" and "does not exist" look the same, so the chosen device resumes when the other is gone, not when no rival choice appeared. The other device leaving settles it whoever chose what, so "Leave the call here" keeps the call on the other device. Unassigned.
- **A device that gives up ends only itself**, so one device's network trouble cannot end a call settled on the other. Unassigned.
- **Waits match the call server's own window** for how long it still lists a device that left. Engineer.
- **An older-version device is never waited on; this device stays muted.** Unmuting would recreate the duplicate; lost credit is recoverable, invented credit is not. The learner pays: they cannot speak until they deal with the other device, and the newer device always drops out. Unassigned.
- **A device that does not carry on keeps nothing** (no transcript, no analytics): the chosen device captured the same opening seconds. Unassigned.
- **A device the call was moved away from keeps what it captured**, because nobody else has that stretch. Timing tells a move from two answers to one ring; when unsure, it is treated as two answers. Unassigned.
- A device that joins a call already under way reads the other person's call state as far back as one membership refresh (two minutes) plus slack; placed or answered calls keep the one-ring floor. Adopting a sibling's call key, falling back to the ring's key, and writing the call clock depend on whether the writer's device holds a live, unexpired membership — never on one membership event id, because the SDK replaces that event every refresh. The race window for a move is the ring's actual lifetime (the longest the device knows, capped at 90 s) plus margin; a learner who moves within it is treated as having answered the same ring, and the earlier device's half is not published.
- **Each device's transcript is kept and merged as one speaker**, because keyed by account one silently replaced the other. No per-device label: it is one person. Unassigned.
- **The transcript reader counts transcripts assembled from several devices**, without naming devices, so duplicate credit is countable. Unassigned.
- **The learner's choice replaces the automatic choice of which device records.** A chosen device with a broken microphone leaves the call unrecorded; the recourse is choosing the other. Unassigned.
- **No credit backstop in v1.** Counting a call's credit once would change the path every analytics write uses, mid-study. Reopen if the studies show duplicate credit in learners' numbers. Analytics owner (unnamed).
- **No minimum app version for calling**, which would refuse learners who did nothing wrong. Instead study participants update their devices or answer on one. Unassigned.
- **Not in v1:** several devices on purpose with different jobs (treated as an accident until per-device roles exist), group calls, and returning to a device chosen against. Follow-ups: [pangeachat/.github#410](https://github.com/pangeachat/.github/issues/410). Unassigned.

## Open questions

- Do staging and production call tokens carry the permission to publish a device's choice? Without it every two-device call shows the older-version prompt, wrongly. The old doc called this unverified and blocking.
- The case against a credit backstop assumed v1 cannot move a call; moves now exist and credit both devices. Does it still hold?
- [voice-video-calls.instructions.md](voice-video-calls.instructions.md) still says the recording device is elected among an account's devices and a transcript is one event per speaker; this doc changes both. Which should say it?

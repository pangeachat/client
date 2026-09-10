# Call recordings + transcript UI redesign — design spec v2 (items 2/3/4/5)

Status: DRAFT for owner review. Revised after a Codex design gate (v1 verdict REVISE; the 6
hardening points are folded in below and marked [gate]). No code lands until approved. Built by
agents (each self-gating with Codex to green); orchestrator runs a cold Codex green over the delta.

Scope: one cohesive redesign of the call transcript/recordings surface
(`lib/routes/chat/calls/transcript_view.dart` + `turn_timeline.dart`):
- item 2 — transcript turns aligned to the recording timeline (ordering vs the audio)
- item 3 — loading states (spinner/shimmer while a half or the merge is pending; error only after a bounded grace)
- item 4 — recordings UI: sticky "Full call" bar on top, expandable per-device rows
- item 5 — karaoke: highlight + auto-scroll the current turn while the Full-call recording plays, tap to seek

Design principle (owner directive): mirror what the client ALREADY does; keep the design language
identical. Every pattern below is one the app already ships (file:line cited).

---

## 1. Root cause recap (item 2) and the recording-timeline model

Confirmed from real call data: NOT a clock bug. `at_ms - offsetMs` already lands each word on the
SFU clock exactly where the recording places its audio. The skew: an APPROXIMATE turn is placed at
`orderKeyMs = at_ms + at_span_ms` (chunk END) so an estimate can't jump ahead in the standalone
list, while the recording plays the turn at its START (`at_ms`). Precise turns already align;
approximate ones lag by their span (measured 3.65s).

Model: give every turn a RECORDING-TIMELINE window, distinct from its standalone printed time.
- `audioStartMs = (segment.atMs - shift) - recordingOriginMs`.
- `audioEndMs   = (segment.orderKeyMs - shift) - recordingOriginMs` (= audioStart + span; == audioStart for a precise turn).
- `shift = transcript.clockShiftFor(half)`; `recordingOriginMs = mergedRow.content.mergedStartSfuMs`.

Preconditions [gate finding 1] — `audioStartMs`/`audioEndMs` are **null** (turn renders, but is not
seek/highlight-eligible) whenever ANY of:
- there is no merged row on screen (no recording to align to), OR
- `!transcript.turnsShareOneClock` for this call, OR the half is not clock-reconciled
  (`half.clockAnchor == null`) — never treat an unreconciled half as `shift = 0` and seek by a raw
  device clock, and
- the half is not among the merge's `source_event_ids` (its audio is not in this file).
A turn whose computed `audioStartMs` is negative (its true start precedes the recording origin) is
clamped to 0 for BOTH highlight and seek — 0 is the start of the file, which was recorded; it is
never null-because-negative. Clamp `audioEndMs` to `[audioStartMs, durationMs]`.

Highlight window rule [gate finding 1] — a precise turn has an empty `[audioStart, audioStart)`
span, so highlight/karaoke never uses `audioEndMs` as the boundary. The ACTIVE turn is the one whose
`audioStartMs <= playhead` with the greatest `audioStartMs` (i.e. each turn is active from its own
start until the NEXT eligible turn's start). This gives precise and approximate turns identical,
non-empty behavior and is order-stable.

What changes / what does NOT:
- Standalone LIST ORDER stays `orderKeyMs`-based (`CallTurn.at`, `turn_timeline.dart` sort) — no
  answer-before-question regression.
- Printed `m:ss` / `by m:ss` LABEL semantics stay exactly as governed
  (`voice-video-calls.instructions.md` "What a turn's time promises"). We ADD a recording-synced
  highlight/seek layer using `audioStartMs`; we do not restate the printed promise.

## 2. Layout (item 4) — sliver composition [gate finding 4]

The dialog body becomes a `CustomScrollView` (today it is a `ListView`, `transcript_view.dart:306`),
inside the existing `FullWidthDialog` Scaffold (the dialog's own `AppBar` with the close button stays).

Slivers, in order:
1. `SliverPersistentHeader(pinned: true)` — the Full-call bar. NOT a bare `SliverAppBar`: its default
   56px toolbar cannot hold a 40-bar player. A `SliverPersistentHeaderDelegate` with
   `minExtent == maxExtent == kFullCallBarHeight` (~84px: the `AudioPlayerWidget` row + a 1px divider),
   an OPAQUE `theme.colorScheme.surface` background (content scrolls cleanly under it), hosting the
   merged `AudioPlayerWidget` (`color/linkColor: colorScheme.primary, fontSize: 14`) + a "Full call"
   label + a chevron toggling section 2b. Rendered only when a merged row exists; otherwise the
   loading/absent state (section 3) occupies the same fixed extent.
2. `SliverToBoxAdapter` — the expandable per-device section (2b), a SEPARATE sliver, not inside the
   header: `AnimatedSize(duration: FluffyThemes.animationDuration, curve: FluffyThemes.animationCurve)`
   swapping `SizedBox.shrink()` <-> the per-device rows (name + `AudioPlayerWidget`, the existing
   `_recordingsSection` row shape relocated). Collapsed by default (D3).
3. `SliverToBoxAdapter` wrapping `TurnTimeline` — NON-LAZY on purpose [gate finding 4]: the timeline
   is already a bounded non-scrolling `Column` (`turn_timeline.dart:129`), so every turn has a live
   `BuildContext` for `Scrollable.ensureVisible`. Do NOT convert turns to a lazy `SliverList` (its
   off-screen children have no context and auto-scroll silently fails). Notes/caveats follow, as today.

Merged and per-device players remain the same shared `AudioPlayerWidget` fed a relabeled `m.audio`
event (`transcript_view.dart:774`), so only one plays at a time (shared `matrix.audioPlayer`,
`voiceMessageEventId` ownership).

## 3. Loading & error states (item 3) [gate finding 3]

Today `_recordings`/`_merged` use `data ?? const []`, so still-loading is indistinguishable from
"none". Replace with an explicit machine for the Full-call bar (and per expected half):

States: PENDING (shimmer, "Preparing full recording…" / "Waiting for {name}'s recording…"), READY
(the real player), UNAVAILABLE (the `_Message` inline note + retry).

Transitions, made concrete [gate finding 3]:
- `graceStartedAt` is stamped once, when the transcript view first has its own halves loaded (a real
  timestamp, threaded in — not read ad hoc).
- Merge status is authoritative from the room: subscribe to `pangea.call_audio_merged` for this call
  (the same read `_merged` does) AND to new `pangea.call_audio` halves, so a late half/merge updates
  the machine rather than a one-shot future.
- PENDING while: a read is in flight, OR (>=1 half present AND no merged row yet AND `now -
  graceStartedAt < kMergeGrace`). `kMergeGrace` is a single bound (~30s) driven by a `Timer`; when it
  fires, `setState` re-evaluates.
- READY as soon as the merged row (or the half) arrives — even after the grace elapsed (late merge
  flips UNAVAILABLE -> READY; acceptable and correct, better than staying dark).
- UNAVAILABLE only after `kMergeGrace` with no merge. Participants are a HINT for "expect a second
  half", never proof one was recorded; the timer, not membership, ends PENDING.
- Retry re-runs the reads (`_retry`) and restarts the grace timer.
- D1 RESOLVED: expected-participant hint + a bounded grace timer (not membership alone). No infinite
  PENDING (timer bounds it); the one late-merge flash (UNAVAILABLE->READY) is accepted over dark-forever.

## 4. Karaoke: highlight + auto-scroll + tap-to-seek (item 5) [gate findings 2 & 6]

`CallPlaybackController` (a `ChangeNotifier`), owns the sync:
- Subscribes to `matrix.audioPlayer.positionStream`, `playerStateStream`, AND `voiceMessageEventId`
  (ownership) [gate finding 2]. Exposes `ValueListenable<int?> activeTurnIndex`.
- Active only while `voiceMessageEventId.value == mergedEventId`. On ANY change of `voiceMessageEventId`
  away from the merged id, CLEAR the active index IMMEDIATELY (do not wait for a position event) —
  starting a per-device half must not leave a stale merged highlight.
- Resolution: greatest `audioStartMs <= positionMs` among seek-eligible turns (section 1), de-duped
  before notifying (as `highlightCurrentText` does, `message_selection_overlay.dart:320`).
- Disposal [gate finding 6]: cancel all three subscriptions and the `Timer` in `dispose`; guard every
  `notifyListeners`/`setState` behind a `mounted`/`_disposed` check (no callback after dispose).
- Tap-to-seek is SERIALIZED [gate finding 2]: an async `seekTo(turn)` that (a) if the merged event
  does not own the shared player, hands the merged event to the player and awaits load, then (b)
  seeks to `audioStartMs`, then (c) plays — never seeks a per-device half. Guard against overlapping
  taps (ignore while a seek is in flight).

Render + interaction [gate findings 4 & 6]:
- Active-turn indicator is NOT color alone [gate finding 6]: a leading accent bar (2-3px, `primary`)
  on the active bubble PLUS a subtle `secondaryContainer` tint (`chat_list_item.dart:67`). Reduced
  motion respected: when `MediaQuery.disableAnimations`, `ensureVisible` uses `Duration.zero` (jump).
- Auto-scroll: `Scrollable.ensureVisible(key.currentContext, duration: 300ms, curve: easeOut,
  alignment: 0.3)` (`course_overview.dart:96`) on the active turn's `GlobalKey`, ONLY while playing and
  ONLY on active-index change; SUSPEND on user scroll (a `NotificationListener<UserScrollNotification>`),
  RESUME on the next play or tap.
- GlobalKeys are keyed by TURN IDENTITY (senderId + segment index), retained across rebuilds and
  pruned when a turn disappears — never index-keyed (recreated keys break `ensureVisible`) [gate 6].
- D4 RESOLVED [gate finding 6]: seeking is an EXPLICIT affordance, not a whole-bubble tap that would
  swallow text selection. The turn's TIME stamp (and avatar) is a `Semantics(button: true, label:
  "Play from {m:ss}")` tap target that seeks; the transcript text stays selectable (long-press/drag
  unaffected). Localize the label; use directional (RTL-safe) layout APIs throughout.

## 5. Reused client patterns (all already shipped)

| Concern | Reuse | Where |
|---|---|---|
| Player + waveform + scrubber + speed | `AudioPlayerWidget` | audio_player.dart:29 |
| Playhead stream + ownership | `matrix.audioPlayer.positionStream` / `voiceMessageEventId` | audio_player.dart:640, matrix.dart:511 |
| Karaoke time-window highlight | `highlightCurrentText` pattern | message_selection_overlay.dart:320 |
| Auto-scroll into view | `Scrollable.ensureVisible` + GlobalKey | course_overview.dart:96 |
| Expand/collapse | `AnimatedSize` + FluffyThemes timings | message.dart:1149 |
| Loading placeholder | `ShimmerBox` | shimmer_box.dart:23 |
| Inline error + retry | `_Message` + `_retry` | transcript_view.dart:1058,220 |
| Active-row tint | `secondaryContainer` on `Material(borderRadius: AppConfig.borderRadius)` | chat_list_item.dart:67 |
| Tokens | borderRadius 18, columnWidth 380, animationDuration 250/easeInOut, bubble roles | app_config.dart:36, themes.dart:9,37,162 |

Sticky header: a custom `SliverPersistentHeaderDelegate` (the app has no existing pinned-non-appbar
header — `sticker_picker_dialog.dart:116` pins a `SliverAppBar`, which is the wrong extent here).

## 6. Model changes

- `CallTurn` gains `audioStartMs`/`audioEndMs` (`int?`), and a stable `key` derived from turn identity.
  Populated in `_turnsOf` only when eligible (section 1); null otherwise. `at` (printed) and list
  order UNCHANGED.
- New `CallPlaybackController`. No wire/schema change — `at_ms`, `at_span_ms`, `offsetMs`,
  `mergedStartSfuMs` are already on events in people's rooms.

## 7. Governed-doc addition (needs owner review — never edited unilaterally)

`voice-video-calls.instructions.md` "What a turn's time promises" stays as-is (printed labels
unchanged). ADD a short subsection "Played against the recording": when a Full-call recording is on
screen, a turn also carries a recording-timeline window anchored at its audio START, used to
highlight/auto-scroll/seek in sync with playback; display-only, changes neither the printed label
nor the standalone order. Draft shown for approval before any doc commit.

## 8. Test plan (TDD, mutation-proven)

- INVARIANCE [gate finding 5]: `CallTurn.at` and the turn ORDER are byte-identical WITH and WITHOUT a
  merged recording — a dedicated before/after test so a `_turnsOf` refactor cannot silently make an
  approximate turn use `atMs` for `at` (which would turn "by 0:07" into "0:03" and reorder). Prove RED
  by mutating `at` to `atMs`.
- `_turnsOf` window math: precise turn -> audioStart == its SFU position - origin, audioEnd == start;
  approximate -> audioStart at chunk START, audioEnd = start + span; null for unreconciled / not-in-
  merge / no-merge; clamp negatives to 0. Prove RED on revert.
- `CallPlaybackController`: position sequence -> correct active index (greatest start <= pos);
  clears immediately on `voiceMessageEventId` change; de-dupes; no notify after dispose. Prove RED.
- Loading machine: PENDING/READY/UNAVAILABLE given (in-flight / half-present-no-merge-within-grace /
  grace-elapsed / late-merge). A fake clock/timer drives expiry. Prove RED.
- Widget: sticky header only with a merged row; chevron expands rows; tap a time seeks; active turn
  shows the accent bar (not color alone); text stays selectable. Reuse `pumpWithRecordings`.
- Full calls bucket stays green; analyze/format/import clean.

## 9. Build decomposition (agents; each self-gates Codex to green)

1. Timeline model — `CallTurn.audioStart/End` + eligibility + `_turnsOf` window math + invariance &
   window tests. (sonnet)
2. `CallPlaybackController` — playhead+ownership -> active-turn, disposal, serialized seek + tests. (sonnet)
3. Karaoke render — `TurnTimeline` accent-bar active state + identity GlobalKeys + ensureVisible +
   user-scroll suspend + reduced-motion + the seek affordance/Semantics. (sonnet)
4. Layout — `CustomScrollView` + `SliverPersistentHeader` Full-call bar + `AnimatedSize` per-device
   sliver, non-lazy turns. (opus — most cross-cutting)
5. Loading/error machine — PENDING/READY/UNAVAILABLE with the grace timer + merge/half subscription. (sonnet)
6. Doc draft for section 7 — proposed, held for owner review (no commit). (orchestrator)

Sequencing: 1->2->3 in order; 4 and 5 parallel after 1; each agent runs its own Codex behaviour+pinning
gate to green before handing back. Orchestrator runs a cold Codex green over the assembled delta, then owner review.

## 10. Decisions (resolved; veto any)

- D1 (loading): expected-participant HINT + a bounded ~30s grace TIMER; error only after it elapses;
  late merge flips to READY. (section 3)
- D2 (highlight): the single most-recent turn (`audioStart <= playhead`, greatest), not every overlap.
- D3 (per-device rows): collapsed by default behind the chevron; Full call is the hero.
- D4 (seek): an explicit accessible affordance on the turn's TIME/avatar (`Semantics` "Play from
  m:ss"); the bubble text stays selectable. NOT a whole-bubble tap.

# Call recordings + transcript UI redesign — design spec v3 (items 2/3/4/5)

Status: DRAFT for owner review. Revised across two Codex design-gate rounds; round-2 refinements
folded in below (marked [g2]). No code lands until approved. Built by agents (each self-gating with
Codex to green); orchestrator runs a cold Codex green over the delta.

Scope: one cohesive redesign of the call transcript/recordings surface
(`lib/routes/chat/calls/transcript_view.dart` + `turn_timeline.dart`):
- item 2 — transcript turns aligned to the recording timeline (ordering vs the audio)
- item 3 — loading states (never an immediate error; error only after a bounded grace)
- item 4 — recordings UI: sticky "Full call" bar on top, expandable per-device rows
- item 5 — karaoke: highlight + auto-scroll the current turn while the Full-call recording plays, tap to seek

Design principle (owner directive): mirror what the client ALREADY does; keep the design language
identical. Every pattern below is one the app already ships (file:line cited).

---

## 1. Recording-timeline model (item 2)

Root cause (from real call data): NOT a clock bug. `at_ms - offsetMs` already lands each word on the
SFU clock where the recording places its audio. The skew is that an APPROXIMATE turn is placed at
`orderKeyMs = at_ms + at_span_ms` (chunk END) so an estimate can't jump ahead in the standalone
list, while the recording plays it at its START (`at_ms`); approximate turns lag by their span (3.65s
measured). Precise turns already align.

Each turn gets a recording-timeline window, distinct from its standalone printed time:
- `audioStartMs = (segment.atMs - shift) - recordingOriginMs`, clamped to `[0, durationMs]`.
- `audioEndMs   = (segment.orderKeyMs - shift) - recordingOriginMs`, clamped to `[audioStartMs, durationMs]`.
- `shift = transcript.clockShiftFor(half)`; `recordingOriginMs = mergedRow.content.mergedStartSfuMs`.

Eligibility — `audioStartMs`/`audioEndMs` are **null** (turn renders, not seek/highlight-eligible) when
ANY of: no merged row on screen; `!transcript.turnsShareOneClock`; `half.clockAnchor == null` (never
treat unreconciled as `shift=0`); or the half is not in the merge's `source_event_ids`.

Ordering of the recording window [g2 tie-break]: the ACTIVE turn is the seek-eligible turn with the
greatest `audioStartMs <= playhead`; TIES (e.g. two pre-origin turns both clamped to 0) are broken by
the turn's standalone order (its `orderKeyMs - shift`, then its list index) so exactly one turn is
active and the choice is deterministic. A precise turn's window is `[audioStart, nextEligibleStart)` —
highlight/karaoke never uses `audioEndMs` as the active boundary, so precise and approximate turns
behave identically.

Recompute on late data [g2]: when a merged row (or a new half) arrives after first paint, the turn
windows are recomputed from the new `mergedStartSfuMs`/`shift` — the windows are derived in `_turnsOf`
and rebuilt whenever the recordings/merged futures update (they already drive a rebuild today).

What does NOT change: `CallTurn.at` (printed time) and the standalone LIST ORDER stay `orderKeyMs`-based
(no answer-before-question regression); the `m:ss` / `by m:ss` LABEL semantics are exactly as governed.

## 2. Layout (item 4) — sliver composition

The dialog body becomes a `CustomScrollView` (today a `ListView`, `transcript_view.dart:306`), inside
the existing `FullWidthDialog` Scaffold (its `AppBar` + close button stay). Slivers:

1. `SliverPersistentHeader(pinned: true)` — the Full-call SLOT. Always present (see section 3); its
   CONTENT is the merged player, or a shimmer, or the error note. Custom
   `SliverPersistentHeaderDelegate` (a 56px `SliverAppBar` cannot hold a 40-bar player). Extent is
   scale-aware [g2]: `minExtent == maxExtent == kBarBase * MediaQuery.textScalerOf(context).scale(1)`
   clamped to a sane max, so it does not clip at 200% text; the "Full call" label ELLIPSIZES (never
   wraps), and degrades to an icon + time if space is tight. Opaque `colorScheme.surface`. Hosts the
   merged `AudioPlayerWidget` (`color/linkColor: primary, fontSize: 14`) + label + a chevron toggling 2.
2. `SliverToBoxAdapter` — the expandable per-device section, a SEPARATE sliver: `AnimatedSize`
   (`FluffyThemes.animationDuration/Curve`) swapping `SizedBox.shrink()` <-> per-device rows (the
   existing `_recordingsSection` shape: name + `AudioPlayerWidget`). Collapsed by default (D3).
3. `SliverToBoxAdapter` wrapping `TurnTimeline` — NON-LAZY, matching TODAY'S behavior: the current
   dialog already builds every turn eagerly (`TurnTimeline` is a non-scrolling `Column`,
   `turn_timeline.dart:129`, inside a `ListView`), so this is status-quo, not a new cost, and it gives
   every turn a live `BuildContext` for `Scrollable.ensureVisible`. Karaoke adds one lightweight
   `GlobalKey` per turn. Virtualizing very long transcripts is a PRE-EXISTING concern (it would apply to
   today's code equally) and is out of scope here; if a bound is ever needed it is a separate follow-up.
   Notes/caveats follow, as today.

Players stay the shared `AudioPlayerWidget` fed a relabeled `m.audio` event (`transcript_view.dart:774`);
one plays at a time (shared `matrix.audioPlayer`, `voiceMessageEventId`).

## 3. Loading & error states (item 3) — a TOTAL machine [g2]

Today `_recordings`/`_merged` use `data ?? const []`, so still-loading looks like "none". Replace with a
machine whose states are EXHAUSTIVE over (reads in flight?) x (halves present?) x (merge present?) x
(grace elapsed?):

- LOADING-READS: either future still in flight -> shimmer.
- READY: a merged row is present -> the merged player. (Also the terminal state once the merge lands.)
- PENDING-MERGE: reads DONE, >=1 half present, no merged row, and `now - graceStartedAt < kMergeGrace`
  -> shimmer "Preparing full recording…". `graceStartedAt` is stamped the instant BOTH reads first
  complete (a real timestamp threaded in), and a `Timer(kMergeGrace)` triggers a re-evaluate.
- NONE: reads DONE and ZERO halves present [g2 — the case that fell through] -> immediately the
  "no recording" note (nothing is coming; do not wait out the grace).
- UNAVAILABLE: reads DONE, >=1 half, no merge, grace ELAPSED -> the `_Message` note + retry.
- A late merge/half arriving in any non-terminal state -> READY (recomputing windows, section 1); the
  one accepted flash is UNAVAILABLE->READY, preferred over staying dark. Retry re-runs the reads and
  RESETS `graceStartedAt` + the timer. Participants are only a HINT that a second half is expected;
  the timer, never membership, ends PENDING-MERGE. D1 RESOLVED.

Per-device rows show the same LOADING/READY per half; a half that never arrives within the grace shows
"Waiting for {name}'s recording…" then drops out (no error row per half).

## 4. Karaoke: highlight + auto-scroll + tap-to-seek (item 5)

`CallPlaybackController` (`ChangeNotifier`) owns the sync:
- Subscribes to `matrix.audioPlayer.positionStream`, `playerStateStream`, AND `voiceMessageEventId`.
- Active only while `voiceMessageEventId.value == mergedEventId`; on ANY change away from it, CLEAR the
  active index IMMEDIATELY (not on the next position event).
- Resolution: greatest `audioStartMs <= positionMs` among eligible turns, tie-broken per section 1,
  de-duped before notifying.
- Disposal: cancel all subscriptions + the `Timer`; guard every notify behind `_disposed` (no callback
  after dispose).
- Tap-to-seek is a SERIALIZED async transaction that RECHECKS OWNERSHIP AFTER EVERY await [g2 race]:
  (a) if the merged event is not the current `voiceMessageEventId`, hand it to the player and await load;
  (b) re-read `voiceMessageEventId` — if it is no longer the merged event (the user started a per-device
  player mid-await), ABORT the transaction (do not seek/play another source); (c) seek to `audioStartMs`;
  (d) play. Overlapping taps: ignore a new tap while one is in flight.

Render + interaction:
- Active indicator is NOT color alone: a leading accent bar (2-3px, `primary`) on the active bubble PLUS
  a `secondaryContainer` tint (`chat_list_item.dart:67`). Reduced motion: `MediaQuery.disableAnimations`
  -> `ensureVisible` uses `Duration.zero`.
- Auto-scroll: `Scrollable.ensureVisible(key.currentContext, duration: 300ms, curve: easeOut, alignment:
  0.3)` on the active turn's key, ONLY while playing and ONLY on active-index change; SUSPEND on
  `UserScrollNotification`, RESUME on next play/tap.
- D4 seek affordance: the turn's TIME/avatar is a `Semantics(button: true)` tap target that seeks; the
  bubble TEXT stays selectable (long-press/drag unaffected). The a11y label announces the RECORDING-
  RELATIVE START, not the printed label [g2]: e.g. a turn printed "by 0:07" whose audio start is 0:03
  announces "Play from 0:03" (localized). Directional (RTL-safe) layout APIs throughout.

## 5. Reused client patterns (all already shipped)

| Concern | Reuse | Where |
|---|---|---|
| Player + waveform + scrubber + speed | `AudioPlayerWidget` | audio_player.dart:29 |
| Playhead + ownership | `matrix.audioPlayer.positionStream` / `voiceMessageEventId` | audio_player.dart:640, matrix.dart:511 |
| Karaoke time-window highlight | `highlightCurrentText` | message_selection_overlay.dart:320 |
| Auto-scroll into view | `Scrollable.ensureVisible` + GlobalKey | course_overview.dart:96 |
| Expand/collapse | `AnimatedSize` + FluffyThemes timings | message.dart:1149 |
| Loading placeholder / error+retry | `ShimmerBox` / `_Message`+`_retry` | shimmer_box.dart:23, transcript_view.dart:1058,220 |
| Active-row tint | `secondaryContainer` | chat_list_item.dart:67 |
| Tokens | borderRadius 18, columnWidth 380, animation 250/easeInOut, bubble roles | app_config.dart:36, themes.dart:9,37,162 |

## 6. Model changes

- `CallTurn` gains `audioStartMs`/`audioEndMs` (`int?`) and a stable `key`. The key is
  `senderId + halfEventId + segmentIndex` [g2 — the half EVENT id, since one sender may write several
  half events and `sender+index` would collide and crash on a duplicate `GlobalKey`]. Keys are retained
  across rebuilds by identity and pruned when a turn disappears; never index-only.
- New `CallPlaybackController`. No wire/schema change — `at_ms`, `at_span_ms`, `offsetMs`,
  `mergedStartSfuMs` are already on events in people's rooms.

## 7. Governed-doc addition (needs owner review — never edited unilaterally)

`voice-video-calls.instructions.md` "What a turn's time promises" stays as-is (printed labels
unchanged). ADD a subsection "Played against the recording": a turn also carries a recording-timeline
window anchored at its audio START, used to highlight/auto-scroll/seek in sync with playback;
display-only, changing neither the printed label nor the standalone order. Draft shown for approval
before any doc commit.

## 8. Test plan (TDD, mutation-proven — each agent NAMES the mutation + the failing assertion)

- INVARIANCE: `CallTurn.at` and turn ORDER byte-identical WITH and WITHOUT a merged recording. Mutation:
  make `at` use `atMs` -> assert "by 0:07" turn's `at` unchanged and no reorder -> RED.
- WINDOW math: precise -> audioStart==SFU-origin, audioEnd==start; approximate -> start at chunk START,
  end=start+span; null for unreconciled/not-in-merge/no-merge; clamp negatives to 0; tie-break
  deterministic. Mutation: drop the `atMs`->`orderKeyMs` distinction / drop the clamp -> RED.
- CONTROLLER: position sequence -> correct active index (greatest start<=pos, tie-broken); clears
  immediately on `voiceMessageEventId` change; de-dupes; seek transaction ABORTS when ownership changes
  mid-await; no notify after dispose. Mutation: remove the post-await ownership recheck -> RED.
- LOADING: every cell of the state table incl. zero-halves-done (NONE) and grace-elapsed (UNAVAILABLE)
  and late-merge (READY + window recompute), driven by a fake clock/timer. Mutation: start the timer
  only when halves>0 -> zero-half case hangs -> RED.
- A11y CONTRACT [g2]: an approximate turn shows "by 0:07" AND its Semantics seek action targets/announces
  0:03. Mutation: announce the printed label -> RED.
- WIDGET: sticky slot present in every state; chevron expands rows; tap time seeks; active turn shows the
  accent bar; text stays selectable. Reuse `pumpWithRecordings`.
- Full calls bucket stays green; analyze/format/import clean.

## 9. Build decomposition (agents; each self-gates Codex to green)

1. Timeline model — `CallTurn.audioStart/End` + eligibility + tie-break + `_turnsOf` + invariance/window tests. (sonnet)
2. `CallPlaybackController` — playhead+ownership -> active index; serialized-with-recheck seek; disposal + tests. (sonnet)
3. Karaoke render in `TurnTimeline` — accent-bar active state + identity GlobalKeys + ensureVisible +
   user-scroll suspend + reduced-motion + the seek affordance/Semantics (announcing audioStart). (sonnet)
4. Loading/error machine in `transcript_view.dart` — the total state table + grace timer + merge/half
   subscription. (sonnet)
5. Layout in `transcript_view.dart` — `CustomScrollView` + `SliverPersistentHeader` slot (scale-aware) +
   `AnimatedSize` per-device sliver + non-lazy turns. (opus — most cross-cutting)
6. Doc draft for section 7 — proposed, held for owner review (no commit). (orchestrator)

Sequencing [g2 — 4 and 5 BOTH edit `transcript_view.dart`, so they are SERIAL, not parallel]: 1 -> 2 ->
3; then 4; then 5 (rebased on 4).

Gating model (owner directive): the ORCHESTRATOR runs the cold Codex gate on EACH agent's diff — the
agents do not self-gate. On RED, the orchestrator root-causes per the red-to-root-cause protocol
(name the rule, not the site) and `SendMessage`s that SAME agent the findings to fix; re-gate; loop
until green (pivot at 4 reds on one dimension, stop at 7-8). Only a green agent's work is accepted and
the next dependent step starts. After all six, the orchestrator runs one final cold green over the
assembled delta, then owner review.

## 10. Decisions (resolved; veto any)

- D1 (loading): expected-participant HINT + a bounded ~30s grace TIMER; NONE immediately on zero halves;
  error only after the timer; late merge -> READY. (section 3)
- D2 (highlight): the single most-recent turn (greatest `audioStart<=playhead`, tie-broken), not every overlap.
- D3 (per-device rows): collapsed by default behind the chevron; Full call is the hero.
- D4 (seek): explicit accessible affordance on the turn's TIME/avatar announcing the recording-relative
  start; bubble text stays selectable. NOT a whole-bubble tap.

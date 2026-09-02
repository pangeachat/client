# Cold Codex review fixes — `satvik/cold-fixes`

Worktree: `.claude/worktrees/txn-keying`. Branch cut from
`satvik/call-device-ownership-v2`. Two commits, **not pushed**.

A cold review of the full production diff (no framing, no per-commit summary)
returned RED on three findings that four earlier scoped gates had passed. All
three were real. A cold RE-RUN on the fixed branch returned RED once more, on a
fourth that only became visible once the empty-half path was correct. Also
real. The earlier gates were each given one commit plus a written
summary, which told the reviewer where to look — the findings all live in the
seams *between* commits.

## Where this landed

| Finding | Real | Commit |
|---|---|---|
| `discardExplainsEmptiness` too broad, ranked above `chunksLost` | yes | `2b52c593dd` |
| `HalfIssue.audioDroppedAtCapture` reaches no sentence | yes | `2b52c593dd` |
| The transcript txn id is re-read per retry attempt | yes | `f7493e671c` |
| A partial discard whose sibling never wrote reads as COMPLETE | yes | `6d62dd6fe0` |

Findings 1 and 2 are one class and got one fix. Finding 3 is its own.

## The class behind 1 and 2

An issue's RANK and its DISPLAY were each decided in one place while `HalfIssue`
grew somewhere else. Nothing forced either site to account for a new value.

- **Rank** now lives in `EmptinessCause` (transcript_assembly.dart), declared
  worst-first: `lost`, `droppedAtCapture`, `heldForASibling`, `suppressedByUs`.
  `explainsEmptiness` refuses any cause with a worse one beside it, reading the
  enum's order rather than restating it. `amountEmptiedBy` is an exhaustive
  switch, so a new cause does not compile until it is mapped.
- **Display**: `emptyHalfNote` (transcript_view.dart) is a switch with no
  default and no wildcard. A new `HalfIssue` fails to compile until somebody
  writes its sentence.

**The trap in this fix, recorded because it nearly shipped.** Blanket
exclusivity — "no OTHER cause may be present" — is wrong. A half that suppressed
one chunk and deferred another is emptied twice over by us, and if neither
explanation holds it falls through to `HalfState.present`, which reads as
*"you did not say anything."* Only a **worse** cause may silence an
explanation. The mechanical test over all 15 cause combinations catches this;
the hand-written cases did not.

## What the class fix surfaced that the review did not name

`HalfIssue.audioHeldByAnotherDevice` had the identical display hole to
`audioDroppedAtCapture` — added to the enum, ranked in `issue`, and falling
through to `callTranscriptNothingRead`, telling a learner their words could not
be READ when nothing had been sent to a reader at all. Two new l10n strings:
`callTranscriptAudioDropped`, `callTranscriptHeldByOtherDevice`.

## Finding 4 — the discard's excuse was never checked

`chunksDiscarded` is excluded from `writerAdmitsGaps` because "a correct discard
loses nothing". That is an assumption about a **different device**, made at
capture time by a device that could not see it, and nothing checked it. A half
that transcribed its early chunks and deferred its tail to a sibling that then
crashed cleared every test — the count is not in `writerAdmitsGaps`, and
`discardExplainsEmptiness` asks for an EMPTY half — and read `present` /
`HalfIssue.none`, with no note on the screen.

Same class as finding 1, one level up: there an explanation displaced a truer
one, here an explanation was **assumed** rather than established.

`EmptinessCause` became `MissingAudio`: one inventory, two exhaustive switches
over it (`amountEmptiedBy`, `leavesAGap`). `leavesAGap` takes `aSiblingWrote` as
a **required** argument, so the question cannot be asked anywhere that cannot
answer it. Assembly answers it with `deviceCount > 1`.

**What coverage can honestly establish:** that another device of this account
published a half for this call and the reader holds it. Nothing more. It cannot
establish that the half spans the discarded stretch — a discarded chunk carries
a count and no position, duration or index; chunk indices do not line up across
devices; and "the sibling's words run past mine" is wrong both ways (a sibling
that recorded the stretch and heard silence writes no segment there; one that
recorded past it may still have lost the chunk that mattered). A sibling that
admits its own gaps needs no test — `_mergeAccounting` ANDs completeness — so
presence is exactly the residual.

**The test that was encoding the bug.** `'a half that still carries words is
complete'` said *"an ordinary handover defers one tail"* and set up ONE device,
which is the opposite of a handover. Its fixture now has the sibling it was
describing; its counterpart is the case that was missing.

**Corner left alone, deliberately.** An EMPTY half with a *covered* discard
(both devices published, both empty) still reports `audioHeldByAnotherDevice`,
whose sentence says the words are on a device that is in fact right here and
also empty. Not false, not maximally informative, and tightening it risks the
`present` → "you did not say anything" regression that mutation 4 caught. Named
rather than fixed.

## Finding 3

`room.client.userID` and `.deviceID` were read inside the publisher closure,
which `CallRecord._publishTranscript` calls once per retry attempt — while
every other field it sends is frozen before the first attempt, with the reason
written beside it. Both are now latched in `CallSession.start` where the
publisher is built: that is the device that did the recording, and by the time
the drain finishes `client.deviceID` answers a different question.

Not latched in `_publishTranscript` beside the counts: the record deliberately
knows nothing about the client, and the session is the seam that already closes
over the room and the clock anchor.

## Mutations watched to fail

| # | Mutation | Bit | Failure |
|---|---|---|---|
| 1 | add a value to `HalfIssue` | yes | compile: `The type 'HalfIssue' isn't exhaustively matched … 'HalfIssue.mutationProbe'` — `non_exhaustive_switch_expression`, transcript_view.dart:513 |
| 2 | add a value to `EmptinessCause` | yes | compile: same error on `amountEmptiedBy`, transcript_assembly.dart:128 |
| 3 | drop the worse-cause guard | yes | `Expected: HalfIssue.audioLost / Actual: HalfIssue.audioHeldByAnotherDevice` — the exact finding-1 defect |
| 4 | widen the guard to blanket exclusivity | yes | `{heldForASibling, suppressedByUs} must not read as silence` — `Expected: false / Actual: <true>` |
| 5 | let the two causes fall through again | yes | `Expected: not 'Nothing could be read from what Ana said' / Actual: 'Nothing could be read from what Ana said'` |
| 6 | read the identity off the live client per attempt | yes | two ids on the wire: `…:@test:…:GHTYAJCE` and `pangea.call_transcript:$anchor:server::` |
| 7 | add a value to `MissingAudio` | yes | compile: BOTH switches fail — `amountEmptiedBy` (:139) and `leavesAGap` (:265) |
| 8 | restore the unconditional discard exclusion | yes | `heldForASibling is a gap must turn on a sibling only for a deferred stretch`; on screen, `Found 0 widgets with text containing may be missing` |
| 9 | drop the read-time check from the state | yes | `heldForASibling leaves a gap with sibling=false, so the half may not claim to be everything that was said` — `Expected: incomplete / Actual: present` |
| 10 | make EVERY discard a gap | yes | the ordinary two-device handover goes `Expected: present / Actual: incomplete` — the other wrong answer |
| 11 | let the new note fall through | yes | `Expected: 'Part of what Ana said was left to another…' / Actual: 'Nothing could be read from what Ana said'` |

## Gates

All four green on the final tree: `flutter analyze` (whole repo, no issues),
`flutter test test/pangea` (4844 pass, 10 skipped), `dart format lib/ test/
--set-exit-if-changed` (0 changed), `import_sorter:main --no-comments
--exit-if-changed` (0 sorted). Toolchain `~/fvm/versions/3.41.4` throughout.
Calls subset went 1271 → 1285: fourteen new tests. One existing fixture was
CORRECTED (the one-device "handover"), no assertion weakened, no gate touched.

**Adding the new `HalfIssue` refused to compile until the screen had a sentence
for it** — the exhaustive switch from `2b52c593dd` earning its keep in real
work rather than in a mutation.

## Open for the owner

`call-device-ownership.instructions.md` names `CallTranscriptContent.txnId` and
the `senderId` its call site passes, but says nothing about the key having to
be **frozen for the operation**. That is the invariant finding 3 broke and it
is now only stated in code comments. Whether it belongs in the doc is an
instructions-doc change and needs review — not made here.

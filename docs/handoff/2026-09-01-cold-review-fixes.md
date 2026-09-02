# Cold Codex review fixes — `satvik/cold-fixes`

Worktree: `.claude/worktrees/txn-keying`. Branch cut from
`satvik/call-device-ownership-v2`. Two commits, **not pushed**.

A cold review of the full production diff (no framing, no per-commit summary)
returned RED on three findings that four earlier scoped gates had passed. All
three were real. The earlier gates were each given one commit plus a written
summary, which told the reviewer where to look — the findings all live in the
seams *between* commits.

## Where this landed

| Finding | Real | Commit |
|---|---|---|
| `discardExplainsEmptiness` too broad, ranked above `chunksLost` | yes | `2b52c593dd` |
| `HalfIssue.audioDroppedAtCapture` reaches no sentence | yes | `2b52c593dd` |
| The transcript txn id is re-read per retry attempt | yes | `f7493e671c` |

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

## Gates

All four green on the final tree: `flutter analyze` (whole repo, no issues),
`flutter test test/pangea` (4837 pass, 10 skipped), `dart format lib/ test/
--set-exit-if-changed` (0 changed), `import_sorter:main --no-comments
--exit-if-changed` (0 sorted). Toolchain `~/fvm/versions/3.41.4` throughout.
Calls subset went 1271 → 1278: seven new tests, no fixture edits.

## Open for the owner

`call-device-ownership.instructions.md` names `CallTranscriptContent.txnId` and
the `senderId` its call site passes, but says nothing about the key having to
be **frozen for the operation**. That is the invariant finding 3 broke and it
is now only stated in code comments. Whether it belongs in the doc is an
instructions-doc change and needs review — not made here.

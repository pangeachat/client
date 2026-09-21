# Join-stamp narrowing — `CaptureElection.joinStampResolution`

Date: 2026-09-01 · Branch: `satvik/call-device-ownership`

## Status, in one sentence

**The committed tree DOES narrow: a discard comparison runs at one millisecond
whenever BOTH devices' join stamps are millisecond-real, and at one second
otherwise.** The change is complete and all four gates were green before the
commit (analyze, `flutter test test/pangea/calls` = 1224 passing, `dart format
--set-exit-if-changed`, `import_sorter --exit-if-changed`).

## The rule as implemented

A stamp `(secondsMs, ms)` is **millisecond-real** iff all three hold:

1. `secondsMs > 0` — there is a coarse reading for the fine one to refine;
2. `ms - secondsMs` is in `[0, 1000)` — the two halves came out of one frame
   and agree, which is also what refuses proto3's absent-reads-as-zero;
3. `ms < ClockAnchor.clockCeilingMs` — it is a clock reading this app would
   believe at all.

(1) and (2) are `ClockAnchor.millisecondRefinement`, promoted out of
`CallMedia._sfuReading` so the transcript's clock anchor and the election share
ONE copy of the window. (3) is added only on the election side, for the reason
`CallRoster.usableJoinTime` gives for applying it to the coarse reading.

`CaptureElection._joinOrdering` then returns **both halves and the resolution
together**:

- both stamps millisecond-real → both `ms` values, `millisecondJoinStampResolution`
  (1ms);
- otherwise → both of the roster's coarse `DateTime`s, `joinStampResolution` (1s);
- either coarse reading missing on that path → `null`, and a null ordering
  refuses.

The comparison itself is unchanged: discard iff
`successor + resolution <= mine`. At 1ms that is a strict inequality.

`joinStampResolution` is now the FALLBACK, not the only value.

## How a mixed-resolution pair falls

**It falls back to the whole second**, and the fine half of the pair is
discarded rather than compared against the other device's coarse half. Mixing
would compare two different measurements — one names an instant, the other the
second it fell in — and in the concrete case tested (ours at +500ms, sibling's
server older than livekit-server v1.8.4) mixing reads as the sibling arriving
500ms first and DESTROYS the tail. Falling back costs a duplicate.

Structurally enforced: `_joinOrdering` returns a record carrying both halves, so
a mixed pair is unrepresentable rather than merely discouraged.

## Identity plumbing

`CallParticipant` now carries the `identity` it was parsed from (required
constructor argument, present on every `parse` return path, carried through
`describedBy`, and added to `state` so the roster's notify predicate stays
derived rather than hand-maintained). `CallRoster` exposes `myIdentity` (from
`_RosterPicture`, taken from `snapshot.me?.identity`) and
`siblingIdentity(deviceId)`. `active_call.dart` reads both and hands
`media.sfuJoinStampsFor(identity)` to the election.

`myIdentity` is deliberately NOT filtered by `usableJoinTime`: an identity is
what the SFU CALLS the device, not a reading, so it survives a membership the
SDK reports as undescribed.

## Mutations run, and whether they bit

| # | Mutation | Bit? | Failure observed |
|---|---|---|---|
| M1 | `millisecondJoinStampResolution` → `Duration(seconds: 1)` | YES | 3 failures, incl. `a successor milliseconds earlier in OUR second takes our tail` — `Expected: true / Actual: <false>` |
| M2 | `_joinOrdering` allowed to take each half from a different source | YES | 4 failures, incl. `a sibling behind an older SFU is compared at the second` — `Expected: false / Actual: <true>` |
| M3 | clock ceiling dropped from `_millisecondJoin` | YES | `a stamp beyond any believable clock is not a reading` — `Expected: false / Actual: <true>` |
| M4 | millisecond resolution → `Duration.zero` (non-strict) | YES | `two devices stamped in the SAME millisecond keep their tails` — `Expected: false / Actual: <true>` |
| M5 | `secondsMs <= 0` guard → `secondsMs < 0` | **NO at first**, YES after | The original assertion used `(secondsMs: 0, ms: noonMs)`, which the WINDOW already refuses, so the guard was untested. A second assertion — `(secondsMs: 0, ms: 500)`, inside the window of a zero coarse half — was added, and the mutation then failed with `a fine stamp with no coarse half to refine is not a reading` — `Expected: false / Actual: <true>`. |
| M6 | `roster.myIdentity` → `'${client.userID}:${client.deviceID}'` (rebuilt) | YES | end-to-end `the SFU millisecond stamps order a pair one second cannot` — `Expected: true / Actual: <false>` |

M5 is the informative one: a mutation that does not bite means the assertion was
not pinning the line it appeared to. The test was strengthened rather than the
line left unproven.

## Edge cases, and which way each falls

Refuse = keep the tail = a possible duplicate. Discard = destroy the tail.

| Case | Falls | Why |
|---|---|---|
| Both stamps ms-real, successor strictly earlier | **DISCARD** | the SFU's own clock states the order outright |
| Both ms-real, same millisecond | **REFUSE** | equality orders nothing at any resolution |
| Both ms-real, successor later | **REFUSE** | it holds none of what came before it |
| Mixed: one ms-real, one coarse-only (`ms == 0`) | **REFUSE** at 1ms; falls to the 1s comparison, which may still discard | two different measurements; the fallback is the answer this rule already gave |
| Either identity absent from the store (device never named) | **REFUSE** at 1ms; falls to 1s | absent is not zero |
| `ms - secondsMs` outside `[0, 1000)` (either sign) | **REFUSE** at 1ms; falls to 1s | a server contradicting itself inside one frame |
| `secondsMs == 0` with a well-formed `ms` | **REFUSE** at 1ms; falls to 1s | a refinement of nothing |
| `ms >= clockCeilingMs` | **REFUSE** at 1ms; falls to 1s | a number the roster would not believe about a clock |
| Fine pair present, roster's coarse readings null | **DISCARD** (the fine pair decides) | the roster's null there means the SDK reported the participant undescribed, where `Participant.joinedAt` answers with a fresh read of THIS device's clock. The store has no such failure mode — it holds only what arrived in a signal frame naming that identity. Documented and tested. |
| `roster.myIdentity == null` (SFU gave no local membership) | **REFUSE** at 1ms; falls to 1s | no key to look the store up by |
| Coarse readings null AND no fine pair | **REFUSE** outright | unchanged from before |

Direction check: narrowing only ADDS discards. If the coarse rule discarded,
the successor's whole second ended before ours began, so its millisecond reading
is strictly earlier too and the fine rule discards as well. Proved by a test
(`a pair the whole-second rule discarded on still discards`), not only argued.

`chunksDiscarded` stays truthful with no change: it counts what
`CallCaptureService._discardOnStop` caused the sink to set aside, and this change
only moves the boolean handed to `setDiscardOnStop`.

## What was NOT verified — assumed rather than observed

- **`room.localParticipant.identity` equals `response.participant.identity`.**
  The store is keyed by the latter and `CallRoster.read` supplies the former.
  Reasoned from livekit_client building the local participant out of the join
  response; NOT observed against a live SFU in this session. If they ever differ,
  the lookup misses and the comparison falls back to the second — the safe
  direction, and silent.
- **The sibling `joined_at_ms` observation** is the earlier session's six-run
  experiment against livekit-server v1.9.1, quoted rather than re-run here.
- Only `test/pangea/calls` was run, not the whole suite. `flutter analyze` is
  repo-wide and green.
- No manual/device testing of an actual two-device handover with the new rule.

## Exact next step for whoever resumes

Nothing is half-done; the next step is verification rather than code:

1. Confirm on staging (or a local two-device run) that
   `CallRoster.myIdentity` and the key `CallMedia` files our own stamp under are
   the SAME string. Log both at the discard site for one call. If they differ,
   the fix is in `CallRoster.read`/the token service, NOT in the election.
2. Run the wider client test suite once, outside this worktree's call scope.
3. `.github/instructions/call-device-ownership.instructions.md` was UNTRACKED at
   dispatch and is committed here with one corrected paragraph (it asserted
   `joinStampResolution` had not changed). Check that against whatever else is
   in flight for that file.

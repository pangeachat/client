# ErrorHandler restore — `satvik/call-device-ownership-v2`

Checkpoint written 2026-09-01. Worktree: `.claude/worktrees/device-ownership`.

## State of `error_handler.dart`

**Fully restored, and committed.** Not main's version, not something in between.
The file on disk is main's copy with the `e`/`m` widening reapplied on top of it;
every change main made since the branch was cut is still present.

Commit `0ff0002ce1` — `fix(errors): let a failure with no exception ring an alarm,
without dropping m`. Three files: `error_handler.dart`,
`test/pangea/calls/call_mini_tile_test.dart`, and the new
`test/pangea/error_handler_message_test.dart`.

## Gate status

| Gate | Result |
| --- | --- |
| `flutter analyze` | **0 errors** (was 8 on the inherited branch) |
| `flutter test test/pangea` | 4785 passed, 10 skipped, **0 failed** |
| `dart format lib/ test/ --set-exit-if-changed` | clean |
| `dart run import_sorter:main --no-comments --exit-if-changed` | clean, 0 files sorted |

No remaining errors. Nothing left uncommitted.

## The conflict this work had to resolve

The task was framed as "the widening was lost before #8654's final push" — an
accident. It was not. Commit `130737ccac`, *"refactor(errors): remove the
silently-dropped m parameter from logError"* (Aug 31, one day before this branch),
removed `m` **deliberately and with review**, and made `e` required. Its reasoning:

- `captureException(e ?? Exception(m))` read `m` only when `e` was null, so 37 call
  sites passed a message that reached `debugPrint` and nothing else.
- It converted the 8 "message only" sites to `e: Exception(<message>)`.
- It explicitly refused to fold messages into `e`, because *"wrapping would change
  e's runtime type and break severityOf/fingerprintOf (#8469)."*

So a verbatim restore of the old file would have re-introduced a defect fixed the
day before. **This is the item a reviewer should look at twice** — see Open question.

## How it was reconciled

`m` is now recoverable from every event it is given to, which is what #8660 actually
wanted, and `e` is nullable, which is what this branch actually needs:

- **`m` alone** → becomes the reported exception, so it is the Sentry title, grouped
  and searchable. This is #8660's own idiom (`e: Exception(msg)`), moved to the sink.
- **`m` beside an `e`** → the caught exception still owns the title and keeps its
  runtime type, so `severityOf` and `fingerprintOf` are untouched; `m` rides on the
  event as the `pangea_report` context (`ErrorHandler.messageContext`). It is *not*
  wrapped, honouring #8660's stated constraint.
- **Neither** → `Exception('no message supplied')`, preserved from the old file.
- **Existing callers** (all pass an `e`, no `m`) produce byte-identical events: no
  context is set and the exception is captured exactly as before.

Untouched from main: the expired-token collapse (#8698), the debug-mode
`presentError` sink (#8677), the 429 error copy (#8705). `_isExpiredTokenError` was
widened to `Object?` only so a null can flow through it (a null is never an expired
token). `severityOf`/`fingerprintOf`/`statusCodeOf` already took `Object?`.

## `shouldReport(null)` — the decision

**Left as `true`.** `shouldReport` is `e is! UnsubscribedException`, so a null already
returned true; no signature change was needed, and none was made.

It exists to suppress exactly one control-flow type — an unsubscribed user reaching a
paid endpoint. A null is not that type. It is the no-exception failure the widening
exists to raise, so returning `false` for it would silently drop precisely the alarm
being restored — the #8660 defect in a different costume. Pinned by a test.

## Mutations run

Every new test was proved by breaking the code, running it, and watching it fail.

| # | Mutation | Bit? | Failure observed |
| --- | --- | --- | --- |
| 1 | Drop the `?? Exception(m ?? ...)` fallback | yes — 5 tests | `TimeoutException after 0:00:05.000000: Future not completed` — **no Sentry event at all** |
| 2 | Remove `setContexts` when an exception is present (the #8660 defect, restored) | yes — 1 test | Expected `'This device could not tell…'`, Actual `'Exception: m.room.member write rejected'` |
| 3 | Fold `m` into `e` by wrapping (throwable only) | yes — 1 test | Expected `same instance as _Exception:<…write rejected>`, Actual the wrapped exception |
| 4 | Realistic fold — scope reads the wrapped object too | yes — 4 tests | fingerprint Expected `['pangea-http','503','GET','/x']`, Actual `[]`; level flipped. **Proves #8660's stated hazard is real and now guarded.** |
| 5 | `shouldReport(null) == false` | yes — 6 tests | 5× `TimeoutException … Future not completed`, plus Expected `true` / Actual `<false>` |
| 6 | Set the message context unconditionally | yes — 1 test | Expected `null`, Actual `{'value': 'none'}` |
| 7 | `logErrorOnce` returns `e != null` | yes — 1 test | Expected `true`, Actual `<false>` |
| 8 | Make the `call_mini_tile` fake's `discarded()` throw | **NO — did not bite** | `All tests passed!` |

**Mutation 8 is the one that did not bite, and that is worth knowing.** The
`_NullSink` in `call_mini_tile_test.dart` is never fed a chunk — the session never
leaves its opening state — so the body of `discarded` is unexercised by any
assertion. It was implemented to record the chunk (as `CallTranscriptSink` does, and
as `RecordingSink` in `call_capture_test.dart` does) because an empty body models the
exact loss the method exists to close; but that choice is correctness-of-modelling,
not something a test currently holds in place.

One test was also caught being **vacuous** mid-review and fixed: the `logErrorOnce`
case asserted a flag it set itself. It now asserts the awaited return value, and
mutation 7 confirms it bites.

## Open question for the owner — needs a human call

This branch re-adds a parameter that a reviewed commit deliberately removed one day
earlier. The reconciliation is defensible and every gate is green, but the underlying
disagreement is a design question, not a code question:

> Should the sink own the "failure with no exception" case (`m`, as restored here), or
> should call sites keep synthesising `e: Exception(<message>)` per #8660's convention?

The argument for the sink: `call_record.dart` passes `e: lastError`, which is
**nullable at runtime** — so the call site would have to write `lastError ?? Exception(m)`
itself, and every future site with a sometimes-absent error re-derives the same idiom.
This codebase's own rule is that a rule copied per call site drifts.

`repos-and-error-handling.instructions.md` says nothing about `m` either way, so
nothing in the instruction docs was contradicted — and nothing there was edited. If
this lands, that doc is probably where the resolution belongs, which needs Will's
sign-off per the instructions-authoring invariant.

## Next step for whoever resumes

Nothing is half-done; the branch is green and resumable. In order:

1. Raise the Open question above with Will before the PR is merged. Ping `ggurdin`
   (author of `130737ccac`) — this touches their change directly.
2. If the sink-owns-it answer holds, add the `m` contract to
   `repos-and-error-handling.instructions.md` (human review required — do not edit it
   unilaterally).
3. Nothing was pushed. The PR is the owner's to open.

# ErrorHandler restore, then withdrawn — `satvik/call-device-ownership-v2`

Checkpoint rewritten 2026-09-01, superseding this file's earlier contents.
Worktree: `.claude/worktrees/device-ownership`.

## Where this landed

**`error_handler.dart` is byte-identical to `origin/main`.** The `m` parameter and
the nullable `e` this branch re-added in `0ff0002ce1` are gone; main's reviewed
signature from `130737ccac` stands unchanged. `git diff origin/main --
lib/pangea/common/utils/error_handler.dart` is empty, and the blob hashes match
(`9882caed00`).

The four call sites that needed the widening now use main's idiom instead. Every
message is preserved verbatim and every one still reaches Sentry.

## The decision, and why

The earlier version of this file left an open question for the owner: should the
sink own the "failure with no exception" case (`m`), or should call sites keep
synthesising `e: Exception(<message>)` per #8660's convention?

**Answered: the call sites.** The widening was reviewed and returned GREEN — it did
not regress #8660 and left existing callers byte-identical — so this is not a
correctness fix. It is a scope reduction. Only one of the four sites truly had no
exception; the other three already passed `e`, which is exactly the redundancy
`130737ccac` deleted across 45 sites.

## The four sites

| Site | Before | Now |
| --- | --- | --- |
| `call_token_repo.dart` `_reportMissingMetadataGrant` | `m` only — the one real no-exception site | `e: Exception(<message>)`. Nothing threw, so the sentence IS the captured exception, which is #8660's own conversion for the 8 message-only sites. |
| `call_record.dart` `finish` (uncredited speech) | `e: lastError` (`Object?`) + `m` | `e: lastError ?? Exception(<message>)` |
| `call_record.dart` `_publishTranscript` (unpublished half) | `e: lastError` (`Object?`) + `m` | `e: lastError ?? Exception(<message>)` |
| `call_roster.dart` `_write` | `e` + `m` | `e` kept, `m` dropped from the signature; the sentence moved to `data` as `CallRoster.attributesUnpublishedCost`. |

### Why the roster's sentence went to `data` rather than being deleted

It says something `e` does not. The thrown object is whatever the SFU signal channel
raised — a five-second timeout, a refusal — and no shape of it says that the recorder
election is running without its capability layer. It cannot be folded into `e`:
wrapping changes the runtime type the severity table and `fingerprintOf` both read,
which is precisely why `130737ccac` deleted these sentences rather than merging them.
`data` is already required at this sink and reaches the event as a breadcrumb, so the
sentence is searchable there. Named as a constant beside `attributesUnpublishedKey`,
so the report and the test that pins it spend one string.

## What a reviewer should look at twice

**`call_record.dart` `_publishTranscript`: the `?? Exception(...)` fallback is
unreachable.** The loop only falls through by throwing three times, so `lastError` is
always non-null there and the sentence — *"This device published no transcript half;
the speaker will read as absent from a call they spoke in"* — never reaches Sentry.
The thrown cause and the loss counts in `data` carry the event instead. This is
exactly how `130737ccac` treated the 37 sites that already passed `e`, so it is the
convention rather than a gap; it is called out because the sentence reads as if it
still ships.

The mirror site in `finish` is the opposite: `_write` swallows its own failures and
`_finish` swallows `CallAnalyticsNotStored`, so **every** way that report is reached
has `lastError == null` and the sentence is always the title.

## Test coverage

`test/pangea/error_handler_message_test.dart` (added by `0ff0002ce1`) was **deleted**.
It cannot compile against main's signature — 15 analyzer errors, all
`undefined_named_parameter: 'm'`, `missing_required_argument: 'e'`, or
`undefined_getter: 'messageContext'`. Verified by restoring it and running
`flutter analyze` on it before removing it again.

Its coverage moved to the call sites, where the question is not what the sink does
with a parameter but whether each alarm actually arrives:

- `call_token_repo_test.dart` — new `what the report carries` group: the sentence is
  the Sentry title, the level is `error`, the claims the token DID carry travel.
- `call_record_test.dart` — the caught cause owns the title (`same(failure)`), and the
  no-exception branch arrives titled by its sentence with `anchored: false`.
- `call_roster_test.dart` — the caught cause owns the title, `data['lost']` carries the
  cost sentence, and the throwable does not.

`test/pangea/calls/call_mini_tile_test.dart` keeps its `0ff0002ce1` change. That was
the `CallAudioSink.discarded` fake, unrelated to the ErrorHandler signature.

## Mutations run

Every new assertion was proved by breaking the code, running it, and watching it fail.

| # | Mutation | Bit? | Failure observed |
| --- | --- | --- | --- |
| 1 | Token-repo sentence replaced with `'no message supplied'` | yes | Expected contains `'The call token carries no canUpdateOwnMetadata grant…'`, Actual `'Exception: no message supplied'` |
| 2 | `finish`'s sentence replaced with `'no message supplied'` | yes | Expected contains `"This call's speech was never credited to the learner"`, Actual `'Exception: no message supplied'` |
| 3 | `_publishTranscript` WRAPS the caught cause (the #8469 hazard) | yes | Expected `same instance as StateError:<Bad state: the homeserver said no>`, Actual `_Exception:<Exception: This device published no transcript half…>` |
| 4 | Roster `'lost'` entry dropped from `data` | yes | Expected the cost sentence, Actual `<null>` |
| 5 | Roster folds the sentence into `e` | yes | Expected `same instance as StateError:<Bad state: Signal request timed out>`, Actual the wrapped `_Exception` |
| 6a | Token-repo report downgraded to `level: warning` | yes | `nothing here is transient; got warning` |
| 6b | `videoGrantClaims` emptied | yes | Expected `['canPublish','canSubscribe','room','roomJoin']`, Actual `[]` |
| 7 | `'anchored'` hardcoded `true` | yes | Expected `false`, Actual `<true>` |
| 8 | Roster cost sentence trimmed to drop the election half | yes | Expected contains `'the recorder election is running without its capability layer'`, Actual the trimmed sentence |

Mutation 6a bit, but its first run reported only
`Expected: <Instance of 'SentryLevel'> / Actual: <Instance of 'SentryLevel'>`, which
says nothing about which way the table went. The assertion now carries a `reason`
naming the level, matching the convention already used in `call_roster_test.dart`.
Re-run under the same mutation, it reads `nothing here is transient; got warning`.

## Gate status

| Gate | Result |
| --- | --- |
| `flutter analyze` | **No issues found** |
| `flutter test test/pangea` | 4792 passed, 10 skipped, **0 failed** (net −5: 12 deleted, 7 added) |
| `dart format lib/ test/ --set-exit-if-changed` | clean |
| `dart run import_sorter:main --no-comments --exit-if-changed` | clean, 0 files sorted |

Toolchain pinned to `~/fvm/versions/3.41.4`. Homebrew Flutter breaks this suite.

## Instruction docs

None changed, and none needed to. `repos-and-error-handling.instructions.md` says
nothing about `m` either way, and `call-device-ownership.instructions.md` — new on
this branch — documents the ownership protocol without prescribing a reporting
signature. The earlier note here, that a resolution might belong in
`repos-and-error-handling.instructions.md`, is moot: main's contract is unchanged, and
its own dartdoc already states why there is no `m`.

## Next step

Nothing is half-done. Not pushed; the PR is the owner's to open.

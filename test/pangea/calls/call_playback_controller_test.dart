import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_playback_controller.dart';
import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';

const _mergedEventId = '\$merged:example.org';
const _otherEventId = '\$other:example.org';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// A [ValueNotifier] that counts its own `addListener`/`removeListener`
/// calls, so a test can prove a listener was actually removed on dispose
/// without touching `ChangeNotifier.hasListeners` -- which is `@protected`,
/// so reading it from a test file trips `invalid_use_of_protected_member`
/// under `flutter analyze`. Counting through the public override avoids
/// that entirely.
class _CountingOwnership extends ValueNotifier<String?> {
  _CountingOwnership(super.value);

  int addCount = 0;
  int removeCount = 0;

  /// Bumped on every read of [value] (the getter, never the setter) since
  /// whenever a test last reset it to 0. Lets a test arm [onRead] to fire on
  /// one SPECIFIC internal `ownership.value` read -- e.g. the one inside
  /// `_awaitWhileOwned`'s return statement -- by counting up to a known
  /// number from a known starting point, rather than guessing at timing.
  int readCount = 0;

  /// Invoked synchronously, with the just-incremented [readCount], every
  /// time [value] is read -- AFTER this read's own return value has already
  /// been captured, so a hook that itself writes [value] (e.g. to simulate
  /// ownership departing right after a specific read observed it) can never
  /// change what THIS read returns, only what the NEXT one does. That
  /// ordering is what makes it possible to deterministically construct "read
  /// N saw the old value, read N+1 sees the new one" -- the exact shape of
  /// the gap between `_awaitWhileOwned`'s verdict and a caller acting on it
  /// -- without depending on real (and in practice unschedulable, since
  /// Dart's `await` chain resolves such a fully-synchronous sequence in one
  /// uninterruptible cascade) microtask-timing races.
  void Function(int readCount)? onRead;

  @override
  String? get value {
    readCount++;
    final result = super.value;
    onRead?.call(readCount);
    return result;
  }

  @override
  void addListener(VoidCallback listener) {
    addCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removeCount++;
    super.removeListener(listener);
  }
}

/// Fakes every dependency [CallPlaybackController] injects, so these tests
/// never touch `just_audio` or `MatrixState`. [startGate]/[seekGate] let a
/// test hold [startMergedPlayer]/[seek] open mid-await, to prove the
/// ownership recheck between transaction steps. [claimsOwnershipOnStart]
/// mirrors the real wiring's side effect of loading the merged event (it
/// claims `voiceMessageEventId`) -- off by default so the abort tests keep
/// full control of [ownership] themselves.
class _Spies {
  final position = StreamController<Duration>.broadcast();
  final playing = StreamController<bool>.broadcast();
  final ownership = _CountingOwnership(null);

  int startCallCount = 0;
  int playCallCount = 0;
  final seeks = <Duration>[];

  Completer<void>? startGate;
  Completer<void>? seekGate;
  bool claimsOwnershipOnStart = false;

  /// Invoked synchronously as the very first thing inside
  /// [startMergedPlayer], before it does anything else -- lets a test give
  /// this action a synchronous prefix that mutates [ownership] BEFORE the
  /// function ever reaches an `await` (or, absent a [startGate], before it
  /// reaches its own `return`), to prove `_awaitWhileOwned` observes a
  /// change made in that window.
  void Function()? onStartMergedPlayerSync;

  Future<void> startMergedPlayer() async {
    onStartMergedPlayerSync?.call();
    startCallCount++;
    final gate = startGate;
    if (gate != null) await gate.future;
    if (claimsOwnershipOnStart) ownership.value = _mergedEventId;
  }

  Future<void> seek(Duration position) async {
    seeks.add(position);
    final gate = seekGate;
    if (gate != null) await gate.future;
  }

  Future<void> play() async {
    playCallCount++;
  }

  CallPlaybackController controller(List<CallTurn> turns) =>
      CallPlaybackController(
        position: position.stream,
        playing: playing.stream,
        ownership: ownership,
        mergedEventId: _mergedEventId,
        turns: turns,
        startMergedPlayer: startMergedPlayer,
        seek: seek,
        play: play,
      );

  Future<void> dispose() async {
    await position.close();
    await playing.close();
  }
}

void main() {
  var nextIdentity = 0;
  CallTurn turn({int? audioStartMs, int? audioEndMs}) => CallTurn(
    senderId: '@a:server',
    name: 'Alice',
    isMe: false,
    at: Duration.zero,
    text: 'hello',
    identityKey: 'turn-${nextIdentity++}',
    audioStartMs: audioStartMs,
    audioEndMs: audioEndMs,
  );

  group('active-index resolution', () {
    test(
      'resolves the eligible turn with the greatest audioStartMs <= the position',
      () async {
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: 0),
          turn(audioStartMs: 1000),
          turn(audioStartMs: 2000),
        ]);
        addTearDown(controller.dispose);

        spies.ownership.value = _mergedEventId;
        spies.position.add(const Duration(milliseconds: 1500));
        await _flush();

        expect(controller.activeIndex.value, 1);
      },
    );

    test(
      'a tie in audioStartMs is broken by display order -- the later turn wins',
      () async {
        // MUTATION: in _resolveActiveIndex, change the tie-break comparison
        // from `start >= bestStart` to `start > bestStart` -- on a tie it would
        // then keep the EARLIER index (0) instead of the later one (1). RED:
        // this assertion expects 1 and would see 0.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: 500),
          turn(audioStartMs: 500),
        ]);
        addTearDown(controller.dispose);

        spies.ownership.value = _mergedEventId;
        spies.position.add(const Duration(milliseconds: 600));
        await _flush();

        expect(controller.activeIndex.value, 1);
      },
    );

    test(
      'no eligible turn (null, or all after the position) resolves to null',
      () async {
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: null),
          turn(audioStartMs: 5000),
        ]);
        addTearDown(controller.dispose);

        spies.ownership.value = _mergedEventId;
        spies.position.add(const Duration(milliseconds: 100));
        await _flush();

        expect(controller.activeIndex.value, isNull);
      },
    );

    test(
      'a position tick recorded before we owned the player never contaminates our resolution',
      () async {
        // MUTATION: delete the `_lastPositionMs = null;` reset at the top of
        // _onOwnershipChanged. RED: the foreign 9000ms reading below survives
        // the ownership change and gets treated as OUR position the instant
        // ownership is gained, resolving to turn 1 (8000 <= 9000) instead of
        // staying null (no owned tick has arrived yet). `_onPosition` itself
        // deliberately carries no ownership check of its own -- see
        // `_lastPositionMs`'s doc comment for why that would be redundant
        // with this reset.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: 0),
          turn(audioStartMs: 8000),
        ]);
        addTearDown(controller.dispose);

        spies.position.add(
          const Duration(milliseconds: 9000),
        ); // some OTHER track's position; we own nothing yet
        await _flush();

        spies.ownership.value =
            _mergedEventId; // gained -- no fresh tick of OUR OWN yet
        await _flush();

        expect(
          controller.activeIndex.value,
          isNull,
          reason:
              'the 9000ms reading belonged to whatever played before we '
              'owned the merged event and must not be reused as if it were '
              'ours',
        );
      },
    );
  });

  group('de-dupe', () {
    test(
      'notifies once per real change, not once per position event',
      () async {
        // Pins the OBSERVABLE contract (exactly one notify per real change),
        // which is what matters to a consumer -- not which line happens to
        // enforce it. `_activeIndexNotifier` is a plain `ValueNotifier`,
        // which already refuses to notify for a same-value assignment, so
        // deleting `_setActiveIndex`'s own
        // `if (newIndex == _activeIndexNotifier.value) return;` guard does
        // NOT flip this test red on its own -- the library covers it
        // regardless. That guard is kept anyway, as a self-documenting
        // restatement of intent (mirroring `highlightCurrentText` in
        // `message_selection_overlay.dart`) and a safeguard against a future
        // change of the underlying storage, not as this test's mutation
        // target.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: 0),
          turn(audioStartMs: 1000),
        ]);
        addTearDown(controller.dispose);

        var notifyCount = 0;
        controller.activeIndex.addListener(() => notifyCount++);

        spies.ownership.value = _mergedEventId; // no notify yet (still null)
        spies.position.add(
          const Duration(milliseconds: 100),
        ); // real change: null -> 0
        await _flush();
        expect(controller.activeIndex.value, 0);
        expect(notifyCount, 1);

        spies.position.add(const Duration(milliseconds: 300)); // still 0
        await _flush();
        spies.position.add(const Duration(milliseconds: 500)); // still 0
        await _flush();
        expect(controller.activeIndex.value, 0);
        expect(notifyCount, 1);

        spies.position.add(
          const Duration(milliseconds: 1200),
        ); // real change: 0 -> 1
        await _flush();
        expect(controller.activeIndex.value, 1);
        expect(notifyCount, 2);
      },
    );
  });

  group('ownership', () {
    test(
      'losing ownership clears the active index synchronously, not on the next position event',
      () async {
        // MUTATION: in _recompute, change
        // `_setActiveIndex(_owns && positionMs != null ? ... : null);` to only
        // call _setActiveIndex when _owns is true (drop the explicit "else
        // clear" branch). RED: activeIndex stays 0 instead of becoming null,
        // since no position event follows the ownership change here -- and
        // nothing is awaited between the write below and the check, so even a
        // MICROTASK-deferred clear would also show red here.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 0)]);
        addTearDown(controller.dispose);

        spies.ownership.value = _mergedEventId;
        spies.position.add(const Duration(milliseconds: 0));
        await _flush();
        expect(controller.activeIndex.value, 0);

        spies.ownership.value = _otherEventId;
        // No await at all: ValueNotifier.notifyListeners fires synchronously,
        // so a genuinely immediate clear must already be visible with
        // nothing awaited in between.
        expect(controller.activeIndex.value, isNull);
      },
    );

    test(
      'regaining ownership requires a fresh position tick before re-activating',
      () async {
        // The old reading belonged to the player instance/track as it stood
        // BEFORE this regain and must not be replayed as if it still applied
        // -- see _lastPositionMs's doc comment.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: 0),
          turn(audioStartMs: 1000),
        ]);
        addTearDown(controller.dispose);

        spies.ownership.value = _mergedEventId;
        spies.position.add(const Duration(milliseconds: 1200));
        await _flush();
        expect(controller.activeIndex.value, 1);

        spies.ownership.value = _otherEventId;
        await _flush();
        expect(controller.activeIndex.value, isNull);

        spies.ownership.value = _mergedEventId; // regained, no fresh tick yet
        await _flush();
        expect(controller.activeIndex.value, isNull);

        spies.position.add(
          const Duration(milliseconds: 200),
        ); // fresh tick under the NEW ownership
        await _flush();
        expect(controller.activeIndex.value, 0);
      },
    );

    test(
      'a controller constructed while already owning resolves the same way once a position tick arrives',
      () async {
        // Not a distinct code path any more (see the constructor's comment):
        // both activeIndex and isPlaying start at their "nothing known yet"
        // default regardless of ownership at construction, and only ever
        // change from a REAL position/playing event. This pins that a
        // pre-set ownership does not need special-casing -- the very first
        // event after construction resolves exactly as it would if ownership
        // had changed to this value instead of having started there.
        final spies = _Spies();
        addTearDown(spies.dispose);
        spies.ownership.value = _mergedEventId; // set BEFORE construction
        final controller = spies.controller([turn(audioStartMs: 0)]);
        addTearDown(controller.dispose);

        expect(controller.activeIndex.value, isNull);

        spies.position.add(const Duration(milliseconds: 100));
        await _flush();

        expect(controller.activeIndex.value, 0);
      },
    );
  });

  group('seekToTurn', () {
    test(
      'a full transaction from non-owner succeeds: load, seek, then play',
      () async {
        final spies = _Spies()..claimsOwnershipOnStart = true;
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        // ownership starts as neither merged nor other -> the load step runs
        // and (per this fake's wiring) claims ownership, letting the
        // transaction proceed all the way through.

        await controller.seekToTurn(0);

        expect(spies.startCallCount, 1);
        expect(spies.seeks, [const Duration(milliseconds: 3000)]);
        expect(spies.playCallCount, 1);
      },
    );

    test(
      'aborts before seeking when ownership changes during the awaited load',
      () async {
        // MUTATION: in _awaitWhileOwned, delete the `watch` listener
        // (return `!_disposed && _owns` instead). RED: seek and play both
        // fire even though ownership moved away mid-load -- this specific
        // scenario also happens to still be caught by a plain post-await
        // `_owns` check, since ownership never comes back; see the ABA test
        // below for the case that requires watching every intermediate
        // change, not just the value at the end.
        final spies = _Spies()..startGate = Completer<void>();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        // ownership starts as neither merged nor other -> forces the load step.

        final pending = controller.seekToTurn(0);
        await _flush();
        expect(spies.startCallCount, 1);

        spies.ownership.value =
            _otherEventId; // someone else took the player mid-load
        spies.startGate!.complete();
        await pending;

        expect(spies.seeks, isEmpty);
        expect(spies.playCallCount, 0);
      },
    );

    test(
      'aborts even when startMergedPlayer reclaims ownership after an interruption (ABA)',
      () async {
        // MUTATION: in _awaitWhileOwned, drop the `watch` listener and
        // return `!_disposed && _owns` (a plain post-await read) instead.
        // RED: because THIS fake's startMergedPlayer claims mergedEventId as
        // its own last step (mirroring the real wiring), a plain post-await
        // read of _owns is true by construction the moment it returns --
        // regardless of the otherEventId selection in between -- so seek and
        // play both fire, resuming a transaction the user had already moved
        // away from. Only watching every intermediate value (not just the
        // one at the end) tells the reclaim apart from a clean load.
        final spies = _Spies()
          ..startGate = Completer<void>()
          ..claimsOwnershipOnStart = true;
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        // ownership starts as neither merged nor other -> forces the load step.

        final pending = controller.seekToTurn(0);
        await _flush();
        expect(spies.startCallCount, 1);

        spies.ownership.value =
            _otherEventId; // the user picks a per-device half mid-load
        spies.startGate!
            .complete(); // load finishes and reclaims mergedEventId anyway
        await pending;

        expect(
          spies.seeks,
          isEmpty,
          reason:
              'the reclaim happened only because THIS transaction finally '
              'finished loading, not because the user asked for the merged '
              'recording again',
        );
        expect(spies.playCallCount, 0);
      },
    );

    test(
      'aborts when startMergedPlayer flips ownership synchronously before its own first suspension',
      () async {
        // MUTATION: revert _awaitWhileOwned's parameter from a thunk back to
        // an already-started future -- change the two call sites back to
        // `_awaitWhileOwned(startMergedPlayer())` /
        // `_awaitWhileOwned(seek(...))`, and _awaitWhileOwned's own
        // signature back to `Future<bool> _awaitWhileOwned(Future<void>
        // action)`. RED: `startMergedPlayer()` is then evaluated as a plain
        // argument expression BEFORE _awaitWhileOwned's own body runs, so
        // its synchronous prefix -- everything up to its first `await`,
        // which here is the whole adversarial flap below, since this fake
        // never awaits anything when no startGate is set -- executes before
        // the `watch` listener exists to see it. seek and play both fire
        // even though the user moved away and only came back because THIS
        // load reclaimed the merged event.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        // ownership starts null (not merged) -> forces the load step, which
        // is where this fake's synchronous hook lives.

        spies.onStartMergedPlayerSync = () {
          spies.ownership.value = _otherEventId; // user grabs a per-device half
          spies.ownership.value =
              _mergedEventId; // and this same load reclaims it -- both
          // writes complete before startMergedPlayer's body reaches an
          // `await` (there is none here, since no startGate is set), i.e.
          // before its Future is even handed back to whichever code called
          // it.
        };

        await controller.seekToTurn(0);

        expect(
          spies.seeks,
          isEmpty,
          reason:
              'ownership left mergedEventId during startMergedPlayer\'s own '
              'synchronous prefix; a watcher registered only once that call '
              'is already running can never see it',
        );
        expect(spies.playCallCount, 0);
      },
    );

    test(
      'aborts before seeking when ownership leaves in the gap between the load verdict and the seek call',
      () async {
        // MUTATION: delete the `if (_disposed || !_owns) return;` guard
        // added right after the load's `_awaitWhileOwned` call (the one
        // this test pins). RED: seek() fires on the source ownership moved
        // to -- _awaitWhileOwned already decided "still owned" for the
        // load, and that decision is exactly what this test flips
        // ownership away from right after; seekToTurn's own resumption
        // after awaiting that verdict is a fresh suspension point nothing
        // was re-checking, so the stale `true` drove straight into
        // `_awaitWhileOwned(seek)`, whose OWN watch listener -- registered
        // only once IT starts -- cannot see a departure that already
        // happened before it existed (listeners fire on change, not on
        // add). play() still correctly does not fire, since the seek's own
        // verdict (decided after seek() already ran) catches it -- proving
        // this gap is invisible to every guard already in place before this
        // fix.
        //
        // Forces the interleaving deterministically, reusing the same
        // _CountingOwnership.onRead technique as the seek-verdict-to-play
        // gap test above: onRead fires AFTER a read has already captured
        // its own return value, so flipping ownership from inside it changes
        // only what the NEXT read sees.
        final spies = _Spies()
          ..startGate = Completer<void>()
          ..claimsOwnershipOnStart = true;
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        // ownership starts null (not merged) -> forces the load step.

        final pending = controller.seekToTurn(0);
        await _flush();
        expect(spies.startCallCount, 1);
        // paused inside startMergedPlayer's gated await; the load's
        // temporary `watch` listener is live.

        spies.ownership.readCount = 0;
        spies.ownership.onRead = (count) {
          // Completing the gate below lets startMergedPlayer's
          // `claimsOwnershipOnStart` write `ownership.value = mergedEventId`,
          // which synchronously fires (1) _onOwnershipChanged's
          // _recomputePlaying, (2) its _recompute, and (3) the load's own
          // `watch` listener -- all three read back the value this same
          // write just set. Read (4) is _awaitWhileOwned's own verdict read
          // for the LOAD call: the one this test targets.
          if (count != 4) return;
          spies.ownership.value = _otherEventId;
        };

        spies.startGate!.complete();
        await pending;

        expect(
          spies.seeks,
          isEmpty,
          reason:
              'ownership left mergedEventId after _awaitWhileOwned decided '
              '"still owned" for the load but before seekToTurn acted on '
              'that decision by starting the seek',
        );
        expect(spies.playCallCount, 0);
      },
    );

    test(
      'disposing in the gap between the load verdict and the seek call also aborts before seeking',
      () async {
        // Same gap as above, cheap to also pin for disposal: the new guard
        // checks `_disposed` first, so a dispose landing in this same
        // window must be caught exactly like a foreign ownership change is.
        final spies = _Spies()
          ..startGate = Completer<void>()
          ..claimsOwnershipOnStart = true;
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        // ownership starts null (not merged) -> forces the load step.

        final pending = controller.seekToTurn(0);
        await _flush();
        expect(spies.startCallCount, 1);

        spies.ownership.readCount = 0;
        spies.ownership.onRead = (count) {
          // Same read (4) as above -- see that test's onRead comment.
          if (count != 4) return;
          controller.dispose();
        };

        spies.startGate!.complete();
        await pending;

        expect(spies.seeks, isEmpty);
        expect(spies.playCallCount, 0);
      },
    );

    test(
      'aborts before playing when ownership changes during the awaited seek',
      () async {
        // MUTATION: same as the load-abort test above, but for the SECOND
        // `_awaitWhileOwned` call (around `seek`). RED: play fires even
        // though ownership moved away mid-seek.
        final spies = _Spies()..seekGate = Completer<void>();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        spies.ownership.value =
            _mergedEventId; // already owns -> load step skipped

        final pending = controller.seekToTurn(0);
        await _flush();
        expect(spies.seeks, [const Duration(milliseconds: 3000)]);

        spies.ownership.value = _otherEventId; // taken mid-seek
        spies.seekGate!.complete();
        await pending;

        expect(spies.playCallCount, 0);
      },
    );

    test(
      'aborts when ownership leaves in the gap between the seek verdict and play()',
      () async {
        // MUTATION: delete the `if (_disposed || !_owns) return;` guard
        // immediately before `await play();` in seekToTurn. RED:
        // _awaitWhileOwned already decided "still owned" for the seek --
        // that decision is exactly what this test flips ownership away
        // right after -- so without a final synchronous re-read, play()
        // fires on a verdict that is already stale by the time it is used.
        //
        // This forces the interleaving deterministically rather than racing
        // a real timer/microtask against it: _CountingOwnership.onRead runs
        // AFTER a read has already captured its own return value (see its
        // doc comment), so flipping `ownership.value` from inside it changes
        // what the NEXT read sees without touching the read that triggered
        // it. A real production race would come from genuine async I/O
        // inside seek()/play() (the real ones talk to a platform channel);
        // Dart resolves an all-synchronous chain like this test's fakes in
        // one uninterruptible cascade, so a `scheduleMicrotask`-based
        // departure can never actually land inside it -- this hook is what
        // makes the scenario reproducible at all in a fast, deterministic
        // unit test.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        addTearDown(controller.dispose);
        spies.ownership.value =
            _mergedEventId; // already owns -> load step skipped, so the
        // only internal `ownership.value` reads left in this transaction
        // are: (1) seekToTurn's own top-of-function `!_owns` check, then (2)
        // _awaitWhileOwned's verdict read for the seek call -- counted below
        // to target (2) precisely instead of guessing at timing.
        spies.ownership.readCount = 0;
        spies.ownership.onRead = (count) {
          if (count != 2) return;
          // _awaitWhileOwned's verdict read for the seek call just captured
          // "still merged" as ITS answer (unaffected by this, since [value]
          // returns the pre-hook value -- see its doc comment); ownership
          // leaves the instant after, simulating the departure landing in
          // the gap between that verdict and seekToTurn acting on it.
          spies.ownership.value = _otherEventId;
        };

        await controller.seekToTurn(0);

        expect(
          spies.seeks,
          [const Duration(milliseconds: 3000)],
          reason: 'the seek itself already committed before ownership left',
        );
        expect(
          spies.playCallCount,
          0,
          reason:
              'ownership left mergedEventId after _awaitWhileOwned decided '
              '"still owned" for the seek but before seekToTurn acted on '
              'that decision',
        );
      },
    );

    test('an in-flight seek ignores an overlapping tap', () async {
      // MUTATION: delete the `_seekInFlight` guard (or drop setting it to
      // true before the first await). RED: both taps reach seek(), so
      // spies.seeks gains a second entry instead of staying at one.
      final spies = _Spies()..seekGate = Completer<void>();
      addTearDown(spies.dispose);
      final controller = spies.controller([
        turn(audioStartMs: 1000),
        turn(audioStartMs: 2000),
      ]);
      addTearDown(controller.dispose);
      spies.ownership.value = _mergedEventId;

      final first = controller.seekToTurn(0);
      await _flush();
      final second = controller.seekToTurn(1); // overlapping -> must be ignored

      spies.seekGate!.complete();
      await Future.wait([first, second]);

      expect(spies.seeks, [const Duration(milliseconds: 1000)]);
      expect(spies.playCallCount, 1);
    });

    test('seeking a turn with no audioStartMs is a no-op', () async {
      // MUTATION: delete `if (startMs == null) return;` and force-unwrap
      // `startMs!` at the seek call site instead. RED: this throws instead
      // of quietly doing nothing (spies.seeks would never even get checked).
      final spies = _Spies();
      addTearDown(spies.dispose);
      final controller = spies.controller([turn(audioStartMs: null)]);
      addTearDown(controller.dispose);
      spies.ownership.value = _mergedEventId;

      await controller.seekToTurn(0);

      expect(spies.startCallCount, 0);
      expect(spies.seeks, isEmpty);
      expect(spies.playCallCount, 0);
    });
  });

  group('isPlaying', () {
    test(
      'tracks the playing stream only while the merged event owns the player',
      () async {
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 0)]);
        addTearDown(controller.dispose);

        expect(controller.isPlaying.value, isFalse);

        spies.playing.add(true); // not yet owning -> stays false
        await _flush();
        expect(controller.isPlaying.value, isFalse);

        spies.ownership.value = _mergedEventId;
        spies.playing.add(true);
        await _flush();
        expect(controller.isPlaying.value, isTrue);

        spies.ownership.value =
            _otherEventId; // lost ownership -> false immediately
        await _flush();
        expect(controller.isPlaying.value, isFalse);
      },
    );

    test(
      'gaining ownership recomputes isPlaying from the last known playing state',
      () async {
        // MUTATION: remove the `_recomputePlaying();` call from
        // _onOwnershipChanged (leaving only the position-side effects there).
        // RED: isPlaying stays false after gaining ownership, since the
        // earlier `true` player-state event was correctly suppressed (not yet
        // ours) and nothing re-derives it once ownership catches up -- with
        // no SECOND playing event in this test, only the ownership-triggered
        // recompute can make this pass.
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 0)]);
        addTearDown(controller.dispose);

        spies.playing.add(
          true,
        ); // the underlying player is already playing SOMETHING else
        await _flush();
        expect(controller.isPlaying.value, isFalse);

        spies.ownership.value =
            _mergedEventId; // now ours -- no NEW playing event follows
        await _flush();

        expect(controller.isPlaying.value, isTrue);
      },
    );
  });

  group('disposal', () {
    test(
      'cancels its subscriptions and stops notifying once disposed',
      () async {
        final spies = _Spies();
        addTearDown(spies.dispose);
        final controller = spies.controller([
          turn(audioStartMs: 0),
          turn(audioStartMs: 5000),
        ]);
        spies.ownership.value = _mergedEventId;
        spies.position.add(const Duration(milliseconds: 0));
        await _flush();
        expect(controller.activeIndex.value, 0);
        expect(spies.position.hasListener, isTrue);
        expect(spies.playing.hasListener, isTrue);
        expect(
          spies.ownership.addCount,
          1,
          reason: 'the constructor registers exactly one ownership listener',
        );
        expect(spies.ownership.removeCount, 0);

        var notifyCount = 0;
        controller.activeIndex.addListener(() => notifyCount++);
        controller.isPlaying.addListener(() => notifyCount++);

        controller.dispose();

        expect(
          spies.position.hasListener,
          isFalse,
          reason: 'dispose must cancel the position subscription',
        );
        expect(
          spies.playing.hasListener,
          isFalse,
          reason: 'dispose must cancel the playing subscription',
        );
        expect(
          spies.ownership.removeCount,
          1,
          reason:
              'dispose must remove the SAME ownership listener the '
              'constructor added, not merely stop reacting to it',
        );

        // MUTATION: delete the `if (_disposed) return;` guard at the top of
        // _setActiveIndex (the sink every mutating path funnels through, per
        // the comment above it). RED: updateTurns's differing resolution below
        // reaches the already-disposed activeIndex notifier and throws ("used
        // after being disposed") instead of quietly no-op'ing.
        expect(
          () => controller.updateTurns([turn(audioStartMs: null)]),
          returnsNormally,
        );
        expect(controller.activeIndex.value, 0);

        // A stray event on a stream we no longer listen to, and a stray
        // ownership write, must not resurrect any callback either.
        spies.position.add(const Duration(milliseconds: 6000));
        spies.ownership.value = _otherEventId;
        await _flush();

        expect(
          notifyCount,
          0,
          reason:
              'no listener attached before dispose may ever fire again '
              'after it',
        );
        expect(controller.dispose, returnsNormally);
      },
    );

    test(
      'removes an in-flight transaction\'s temporary ownership watcher immediately, not once it settles',
      () async {
        // MUTATION: delete the `for (final watch in _activeOwnershipWatches)`
        // cleanup loop in dispose() (leaving only
        // `ownership.removeListener(_onOwnershipChanged)`). RED: removeCount
        // stays at 1 immediately after dispose instead of 2 -- the
        // in-flight seek's temporary watcher (added by _awaitWhileOwned)
        // would otherwise stay registered on `ownership` until the gated
        // seek below finally completes, or forever if it never did.
        final spies = _Spies()..seekGate = Completer<void>();
        addTearDown(spies.dispose);
        final controller = spies.controller([turn(audioStartMs: 3000)]);
        spies.ownership.value =
            _mergedEventId; // already owns -> load step skipped

        final pending = controller.seekToTurn(0);
        await _flush(); // now inside the awaited seek() -- its watcher is live
        expect(
          spies.ownership.addCount,
          2,
          reason: 'the constructor listener plus this transaction\'s watcher',
        );

        controller.dispose();

        expect(
          spies.ownership.removeCount,
          2,
          reason:
              'both listeners must be gone immediately on dispose, not '
              'left registered until the pending seek happens to finish',
        );

        spies.seekGate!.complete(); // let the disposed transaction unwind
        await pending;
      },
    );
  });
}

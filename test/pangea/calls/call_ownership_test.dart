import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_ownership.dart';

void main() {
  // A fixed origin so every `now` in a test is an offset from one instant. The
  // arbiter takes `now` explicitly, so no fake clock is needed.
  final t0 = DateTime.utc(2026, 1, 1, 12);

  OwnershipDecision noSibling(CallOwnership o, DateTime now) => o.update(
    presentSiblingIds: const {},
    silentSiblingIds: const {},
    siblingClaimObserved: false,
    now: now,
  );

  OwnershipDecision sighting(
    CallOwnership o,
    DateTime now, {
    Set<String> present = const {'B'},
    Set<String> silent = const {},
    bool claim = false,
  }) => o.update(
    presentSiblingIds: present,
    silentSiblingIds: silent,
    siblingClaimObserved: claim,
    now: now,
  );

  group('CallOwnership — the ordinary call', () {
    test('a device that sees no sibling carries on and resumes', () {
      // doc:150 — no sibling remains is an ordinary call.
      final d = noSibling(CallOwnership(), t0);
      expect(d.resume, isTrue);
      expect(d.carriedOn, isTrue);
      expect(d.holdMedia, isFalse);
      expect(d.prompt, OwnershipPromptKind.none);
      expect(d.endSelf, isFalse);
    });
  });

  group('CallOwnership — silence on first sighting', () {
    test('the first reading with a sibling holds media, before any tick', () {
      // doc:146,215 — close and hold on the FIRST sighting, no confirmation
      // delay. The prompt waits; the mute does not.
      final d = sighting(CallOwnership(), t0);
      expect(d.holdMedia, isTrue);
      expect(d.carriedOn, isFalse);
      expect(d.prompt, OwnershipPromptKind.none);
    });

    test('an echo shorter than a tick shows no prompt and then resumes', () {
      // doc:216,257 — a sibling gone inside the tick costs a dropout and no
      // prompt.
      final o = CallOwnership();
      expect(sighting(o, t0).prompt, OwnershipPromptKind.none);
      final gone = noSibling(o, t0.add(const Duration(seconds: 1)));
      expect(gone.resume, isTrue);
      expect(gone.carriedOn, isTrue);
    });
  });

  group('CallOwnership — the choice prompt is tick-gated', () {
    test('the choice appears only after one continuous tick', () {
      // doc:151,216.
      final o = CallOwnership();
      expect(sighting(o, t0).prompt, OwnershipPromptKind.none);
      expect(
        sighting(o, t0.add(kPromptTick)).prompt,
        OwnershipPromptKind.choice,
      );
    });
  });

  group(
    'CallOwnership — the older-version prompt is tick-gated (defect 3)',
    () {
      test('a silent sibling within its tick shows no prompt yet', () {
        // doc:191,216 — an updated sibling is briefly silent before its `no`
        // lands; within the tick it must not be labelled an older build.
        final d = sighting(CallOwnership(), t0, silent: const {'B'});
        expect(d.holdMedia, isTrue);
        expect(d.prompt, OwnershipPromptKind.none);
      });

      test(
        'a silent sibling past its own tick shows the older-version prompt',
        () {
          // doc:153.
          final o = CallOwnership();
          sighting(o, t0, silent: const {'B'});
          final d = sighting(o, t0.add(kPromptTick), silent: const {'B'});
          expect(d.prompt, OwnershipPromptKind.olderVersion);
          expect(d.holdMedia, isTrue);
        },
      );
    },
  );

  group('CallOwnership — Use this device', () {
    test('a claim publishes, holds, then resumes when the sibling is gone', () {
      // doc:146,170 — the chosen device resumes on the sibling's DEPARTURE, not
      // on the tap.
      final o = CallOwnership();
      sighting(o, t0);
      o.chooseThisDevice();
      final claimed = sighting(o, t0.add(const Duration(seconds: 1)));
      expect(claimed.announceChosen, isTrue);
      expect(claimed.holdMedia, isTrue);
      expect(claimed.resume, isFalse);
      final resumed = noSibling(o, t0.add(const Duration(seconds: 2)));
      expect(resumed.resume, isTrue);
      expect(resumed.carriedOn, isTrue);
    });

    test('a claimed device unmutes at the bounded wait regardless', () {
      // doc:218.
      final o = CallOwnership();
      sighting(o, t0);
      o.chooseThisDevice();
      sighting(o, t0); // reconcile the tap: claimedAt = t0.
      final d = sighting(o, t0.add(kChosenUnmuteAfterClaim));
      expect(d.resume, isTrue);
      expect(d.announceChosen, isTrue);
      expect(d.carriedOn, isTrue);
    });
  });

  group('CallOwnership — a silent sibling dominates a claim (defect 2)', () {
    test(
      'a claimed device does NOT unmute while a silent sibling is present',
      () {
        // doc:182,188,254 — the bounded wait may never be applied against a
        // sibling that cannot leave. Rule 4 (silent) must dominate rule 5
        // (claimed): at the unmute instant the device gives up, it does not
        // resume.
        final withSilent = CallOwnership();
        sighting(withSilent, t0);
        withSilent.chooseThisDevice();
        sighting(withSilent, t0); // claimedAt = t0, firstSighting = t0.
        final held = sighting(
          withSilent,
          t0.add(kChosenUnmuteAfterClaim),
          present: const {'B', 'C'},
          silent: const {'C'},
        );
        expect(
          held.resume,
          isFalse,
          reason: 'a silent sibling suppresses unmute',
        );

        // Control: same instant, no silent sibling -> it DOES resume. This is what
        // proves the assertion above bites the rule-4-before-rule-5 ordering.
        final noSilent = CallOwnership();
        sighting(noSilent, t0);
        noSilent.chooseThisDevice();
        sighting(noSilent, t0);
        final resumed = sighting(noSilent, t0.add(kChosenUnmuteAfterClaim));
        expect(resumed.resume, isTrue);
      },
    );
  });

  group('CallOwnership — Leave the call here', () {
    test('ends this device immediately with CONTINUING, no wait', () {
      // doc:164 — a deliberate leave needs no claim; the sibling is present, so
      // the call continues there.
      final o = CallOwnership();
      sighting(o, t0);
      o.leaveHere();
      final d = sighting(o, t0);
      expect(d.endSelf, isTrue);
      expect(d.endReason, LeaveReason.continuing);
      expect(d.carriedOn, isFalse);
    });
  });

  group('CallOwnership — glare, resolved with no clock (doc:248,249)', () {
    test('observing a sibling claim ends this device (CONTINUING)', () {
      // doc:152.
      final d = sighting(CallOwnership(), t0, claim: true);
      expect(d.endSelf, isTrue);
      expect(d.endReason, LeaveReason.continuing);
      expect(d.carriedOn, isFalse);
    });

    test('both claim and both read -> both end', () {
      // doc:248 — this device tapped useThis AND observes the sibling's claim.
      // Rule 2 dominates the pending tap, so it ends without publishing.
      final o = CallOwnership();
      sighting(o, t0);
      o.chooseThisDevice();
      final d = sighting(o, t0, claim: true);
      expect(d.endSelf, isTrue);
      expect(
        d.announceChosen,
        isFalse,
        reason: 'a claim observed drops the pending tap; nothing is published',
      );
    });

    test('one-way visibility -> the reader ends, the other survives', () {
      // doc:249. The reader (sees the claim) ends; the other never reads a
      // claim, holds as claimed, then resumes when the reader is gone.
      final reader = sighting(CallOwnership(), t0, claim: true);
      expect(reader.endSelf, isTrue);

      final survivor = CallOwnership();
      sighting(survivor, t0);
      survivor.chooseThisDevice();
      expect(sighting(survivor, t0).holdMedia, isTrue); // claimed, waiting.
      final resumed = noSibling(survivor, t0.add(const Duration(seconds: 1)));
      expect(resumed.resume, isTrue);
    });
  });

  group('CallOwnership — the stale tap (defect 3)', () {
    test(
      'a Use-this tap racing an observed claim is dropped, never published',
      () {
        // The failing case: a tap queued just before this device processed the
        // sibling's claim would, if it published, make both end. It must not.
        final o = CallOwnership();
        sighting(o, t0);
        o.chooseThisDevice();
        final d = sighting(o, t0.add(const Duration(seconds: 1)), claim: true);
        expect(d.endSelf, isTrue);
        expect(d.announceChosen, isFalse);
      },
    );

    test(
      'a departure clears a pending tap so a stale leave never acts later',
      () {
        // doc:158,163 — rule 1 forgets the pending tap. A leaveHere set before the
        // sibling left must not end the device on a LATER, unrelated sighting.
        final o = CallOwnership();
        sighting(o, t0);
        o.leaveHere();
        expect(noSibling(o, t0.add(const Duration(seconds: 1))).resume, isTrue);
        final later = sighting(o, t0.add(const Duration(seconds: 2)));
        expect(
          later.endSelf,
          isFalse,
          reason: 'the pending leaveHere was cleared on departure',
        );
        expect(later.holdMedia, isTrue);
      },
    );
  });

  group('CallOwnership — the give-up timer (doc:217,222)', () {
    test(
      'a not-chosen device ends only itself at the window, reason ENDED',
      () {
        final o = CallOwnership();
        sighting(o, t0);
        final d = sighting(o, t0.add(kGiveUpAfterSighting));
        expect(d.endSelf, isTrue);
        expect(d.endReason, LeaveReason.ended);
        expect(d.carriedOn, isFalse);
      },
    );

    test('the give-up is cancelled the moment the sibling leaves', () {
      // doc:156 — a departure resolves the ambiguity; the timer must not fire
      // after the thing it waited for has happened.
      final o = CallOwnership();
      sighting(o, t0);
      final d = noSibling(o, t0.add(kGiveUpAfterSighting));
      expect(d.endSelf, isFalse);
      expect(d.resume, isTrue);
    });

    test('a give-up against a silent sibling is ENDED, not CONTINUING', () {
      // doc:44,144,222 — no positive evidence, so the message must not claim the
      // call continues.
      final o = CallOwnership();
      sighting(o, t0, silent: const {'B'});
      final d = sighting(o, t0.add(kGiveUpAfterSighting), silent: const {'B'});
      expect(d.endSelf, isTrue);
      expect(d.endReason, LeaveReason.ended);
    });
  });
}

/// The arbiter for "two devices, one call"
/// (call-device-ownership.instructions.md).
///
/// Pure and level-triggered: [CallOwnership.update] is handed the current roster
/// reading on every recompute and re-derives the WHOLE decision from it, so a
/// late tap or a changed picture is judged against the situation as it is now,
/// never as it was when a prompt appeared. It keeps only the minimum latched
/// state a single reading cannot carry: when a sibling was first seen
/// (continuously), when this device claimed, the learner's pending tap, and
/// whether this device has carried on.
///
/// Nothing here acts on the ABSENCE of a signal. An unheard claim and no claim
/// read identically, so a sibling that has published nothing is SILENT — never
/// "gone", and never "older build" until it has been continuously present for a
/// full prompt tick. Every transition below is a state the roster can point at.
library;

/// What one of this account's other devices has published about being the
/// device that carries on with the call.
enum ChosenState {
  /// Published nothing this build can read — an older build, or a write still on
  /// the wire. Not a statement: never claimed against, never waited on.
  silent,

  /// Published that it is NOT the chosen device. The participation signal every
  /// device on this protocol writes unconditionally from the moment it joins,
  /// which is what makes [silent] mean "does not speak this protocol".
  notChosen,

  /// Published that it is carrying on. Positive evidence, and the only thing
  /// that ends a sibling by observation.
  chosen,
}

/// Which prompt, if any, this device shows the learner.
enum OwnershipPromptKind {
  none,

  /// "This call is open on two of your devices" — pick one to carry on with.
  choice,

  /// "Your other device can't leave this call on its own" — the sibling does not
  /// speak this protocol, so the only action is to leave here.
  olderVersion,
}

/// Why a device left, decided HERE and never at the leave site — so no path can
/// invent a "the call moved" message for a call that actually ended.
enum LeaveReason {
  /// Positive evidence the call carries on elsewhere: an observed sibling claim,
  /// or a deliberate "leave the call here" with a sibling still present.
  continuing,

  /// A give-up timer fired with no such evidence. Nobody chose, so the call is
  /// ending — not moving.
  ended,
}

enum _PendingChoice { none, useThis, leaveHere }

/// One recompute's verdict. Immutable; the caller applies it.
class OwnershipDecision {
  /// Close and HOLD the microphone and camera closed. The caller forces them
  /// closed and refuses to reopen them until a later decision clears this.
  final bool holdMedia;

  /// Whether this device carried on with the call. The finish seam writes no
  /// transcript half and no analytics when this is false.
  final bool carriedOn;

  final OwnershipPromptKind prompt;

  /// Publish `pangea_chosen: yes`. Only ever true through a reconciled `useThis`
  /// intent, so a button can never publish a claim directly.
  final bool announceChosen;

  /// End this device — leave the call locally.
  final bool endSelf;

  /// The reason to surface when [endSelf] is set; null otherwise.
  final LeaveReason? endReason;

  /// Restore the learner's pre-hold microphone and camera. The survivor's exit
  /// from the held state, and the ordinary call when no sibling remains.
  final bool resume;

  const OwnershipDecision({
    this.holdMedia = false,
    this.carriedOn = true,
    this.prompt = OwnershipPromptKind.none,
    this.announceChosen = false,
    this.endSelf = false,
    this.endReason,
    this.resume = false,
  });
}

/// How long a sibling must be continuously visible before its silence reads as
/// an older build and before the choice prompt appears — one presence tick.
const Duration kPromptTick = Duration(seconds: 2);

/// How long a device that has NOT been chosen waits, from when it FIRST saw a
/// sibling, before ending only itself. Matches the peer grace window.
const Duration kGiveUpAfterSighting = Duration(seconds: 20);

/// How long a device that HAS claimed waits, from when it claimed, before
/// unmuting regardless — matched to the SFU's departure retention. A SEPARATE
/// constant from [kGiveUpAfterSighting] that happens to share its value, so
/// tuning one never silently moves the other.
const Duration kChosenUnmuteAfterClaim = Duration(seconds: 20);

/// Decides, on every roster recompute, whether this device holds its media,
/// prompts, claims, ends, or resumes.
class CallOwnership {
  DateTime? _firstSightingAt;
  final Map<String, DateTime> _siblingFirstSeen = {};
  DateTime? _claimedAt;
  _PendingChoice _pending = _PendingChoice.none;
  bool _carriedOn = true;

  /// Whether this device carried on. Read at the finish seam.
  bool get carriedOn => _carriedOn;

  /// When this device published its claim, or null. Visible for tests.
  DateTime? get claimedAt => _claimedAt;

  /// The learner tapped "Use this device". Sets INTENT only — [update]'s
  /// reconcile decides whether it becomes a claim, and DROPS it if a sibling has
  /// already claimed. A button never publishes a claim itself.
  void chooseThisDevice() => _pending = _PendingChoice.useThis;

  /// The learner tapped "Leave the call here". Sets INTENT only.
  void leaveHere() => _pending = _PendingChoice.leaveHere;

  /// A fresh call. Everything the previous one latched says nothing about this.
  void reset() {
    _firstSightingAt = null;
    _siblingFirstSeen.clear();
    _claimedAt = null;
    _pending = _PendingChoice.none;
    _carriedOn = true;
  }

  /// Re-derives the whole decision from the current reading.
  ///
  /// [presentSiblingIds] is every one of this account's OTHER devices the SFU
  /// currently names in this call; [silentSiblingIds] is the subset that has
  /// published no readable `pangea_chosen`; [siblingClaimObserved] is whether
  /// any present sibling has published a claim.
  OwnershipDecision update({
    required Set<String> presentSiblingIds,
    required Set<String> silentSiblingIds,
    required bool siblingClaimObserved,
    required DateTime now,
  }) {
    // Per-sibling first-seen: add newcomers, forget the departed. Its own clock
    // per sibling is what keeps a just-joined device's not-yet-landed `no` from
    // being read as an older build.
    _siblingFirstSeen.removeWhere((id, _) => !presentSiblingIds.contains(id));
    for (final id in presentSiblingIds) {
      _siblingFirstSeen.putIfAbsent(id, () => now);
    }

    // RULE 1 — no sibling. Resume as the survivor (or an ordinary call that was
    // never held), and forget everything the ambiguity latched, the pending tap
    // included: a departure has resolved it, so a stale tap must not still act.
    if (presentSiblingIds.isEmpty) {
      _firstSightingAt = null;
      _claimedAt = null;
      _pending = _PendingChoice.none;
      _carriedOn = true;
      return const OwnershipDecision(resume: true, carriedOn: true);
    }

    final firstSeen = _firstSightingAt ??= now;

    // RULE 2 — a sibling's claim is observed. End, whatever this device did, and
    // DROP any pending tap. This one rule is the glare resolution AND the
    // stale-tap guard: a `useThis` that raced the claim is discarded here and
    // never publishes.
    if (siblingClaimObserved) {
      _pending = _PendingChoice.none;
      _carriedOn = false;
      return const OwnershipDecision(
        endSelf: true,
        endReason: LeaveReason.continuing,
        carriedOn: false,
      );
    }

    // RULE 3 — reconcile the pending tap against the current picture. The ONLY
    // site that ever publishes a claim.
    if (_pending == _PendingChoice.leaveHere) {
      _carriedOn = false;
      return const OwnershipDecision(
        endSelf: true,
        endReason: LeaveReason.continuing,
        carriedOn: false,
      );
    }
    if (_pending == _PendingChoice.useThis) {
      _pending = _PendingChoice.none;
      _claimedAt ??= now;
      // Fall through with a claim now latched.
    }

    // A silent sibling continuously present for a full tick is an older build;
    // one still inside its tick has simply not published its `no` yet.
    final siblingOld = silentSiblingIds.any((id) {
      final seen = _siblingFirstSeen[id];
      return seen != null && now.difference(seen) >= kPromptTick;
    });

    // RULE 4 — a silent sibling is present. Dominates the claimed-hold below: a
    // silent sibling cannot leave, so a claim may not buy a bounded wait that
    // would unmute into a duplicate. Hold, give up at the window, and show the
    // older-version prompt only once the silence is past a tick.
    if (silentSiblingIds.isNotEmpty) {
      _carriedOn = false;
      if (now.difference(firstSeen) >= kGiveUpAfterSighting) {
        return const OwnershipDecision(
          endSelf: true,
          endReason: LeaveReason.ended,
          carriedOn: false,
        );
      }
      return OwnershipDecision(
        holdMedia: true,
        carriedOn: false,
        prompt: siblingOld
            ? OwnershipPromptKind.olderVersion
            : OwnershipPromptKind.none,
        // An existing claim persists until this device leaves; no NEW claim is
        // started against a silent sibling.
        announceChosen: _claimedAt != null,
      );
    }

    // RULE 5 — this device has claimed, against participating siblings only.
    final claimed = _claimedAt;
    if (claimed != null) {
      if (now.difference(claimed) >= kChosenUnmuteAfterClaim) {
        _carriedOn = true;
        return const OwnershipDecision(
          resume: true,
          announceChosen: true,
          carriedOn: true,
        );
      }
      _carriedOn = false;
      return const OwnershipDecision(
        holdMedia: true,
        announceChosen: true,
        carriedOn: false,
      );
    }

    // RULE 6 — all siblings participating, this device has not chosen. Hold,
    // give up at the window, and offer the choice once the sibling has been
    // visible for a tick.
    _carriedOn = false;
    if (now.difference(firstSeen) >= kGiveUpAfterSighting) {
      return const OwnershipDecision(
        endSelf: true,
        endReason: LeaveReason.ended,
        carriedOn: false,
      );
    }
    return OwnershipDecision(
      holdMedia: true,
      carriedOn: false,
      prompt: now.difference(firstSeen) >= kPromptTick
          ? OwnershipPromptKind.choice
          : OwnershipPromptKind.none,
    );
  }
}

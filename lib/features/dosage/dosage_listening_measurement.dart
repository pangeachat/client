import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';

/// What ONE `TtsController.tryToSpeak` call says about its own measurement.
///
/// **Why this is a required argument and not an optional one.** Every call to
/// `tryToSpeak` plays target-language audio at a learner, so every call is
/// listening, and the served number is a TOTAL — a path that measures nothing
/// does not produce a gap in a slice, it produces an undercount in the headline
/// figure. Optional instrumentation makes forgetting it the default: a new
/// read-aloud path compiles, analyzes clean, passes every behavioural test, and
/// silently shortens a teacher-visible total. Required-with-an-explicit-opt-out
/// turns that omission into a compile error, which is the only form of the rule
/// that survives the next person who has never read this file.
///
/// **Why a type and not a bare category.** Naming a category is not enough to be
/// measured: a probe also has to be opened before playback and closed after it,
/// in a `finally`, without awaiting anything. Handing `tryToSpeak` a category and
/// leaving the bracketing to the caller would leave exactly the hole this type
/// closes — a site that names a category and still counts nothing. So a caller
/// hands over a PROBE it has already built (only the caller knows the room and
/// the account), and the bracketing happens once, centrally, in `tryToSpeak`.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md, D-V2-1.
@immutable
class DosageListeningMeasurement {
  /// This playback IS measured, as [probe]'s category.
  ///
  /// The probe carries the category and the room, both of which only the caller
  /// knows — `tryToSpeak` serves automatic read-aloud, toolbar-open read-aloud,
  /// word taps and choice taps through one entry point and cannot tell them
  /// apart. Build a FRESH probe per call: it holds a running measurement.
  const DosageListeningMeasurement.measured(DosageTtsListeningProbe this.probe)
    : exemption = null;

  /// This playback is deliberately NOT measured, for [exemption].
  ///
  /// Not "this is not listening" — every one of these surfaces is listening.
  /// It is an admission that this build cannot yet express it on the wire, and
  /// it is written at the call site so the undercount is visible in the source
  /// rather than inferable only by counting emitters.
  const DosageListeningMeasurement.notMeasured(
    DosageListeningExemption this.exemption,
  ) : probe = null;

  /// The open measurement, or null when this call is exempt.
  final DosageTtsListeningProbe? probe;

  /// Why nothing is measured, or null when it is.
  final DosageListeningExemption? exemption;
}

/// Why a read-aloud path that IS listening still emits nothing.
///
/// Every member is a blocker with an owner, not a judgement that the surface
/// does not matter. They exist so "this is not counted" is a named, greppable
/// state with a reason attached, rather than the absence of a line of code.
///
/// Both members are blocked on the same first thing: **the category vocabulary
/// is closed on the server** (`app/analytics/dosage/audio_categories.py` in
/// admin-dash-api validates both a playback's and a declaration's `category`
/// against a fixed set). A client that invented a category would not merely fail
/// to count these surfaces — the unknown value 422s the WHOLE batch, and since a
/// batch carries every category's coverage declaration alongside its events, one
/// unknown category takes the four categories that DO work down with it. So the
/// vocabulary grows on the server first, and only then here.
enum DosageListeningExemption {
  /// The surface has a room; it is waiting only on a category that describes it.
  ///
  /// None of the four listening categories does. They are all about a MESSAGE —
  /// a voice message from a peer, a message read aloud on arrival, a message the
  /// speaker button was tapped on, a message the toolbar was opened on — and
  /// these surfaces play a WORD or a drill choice. Folding them into `tap_read`
  /// (the only learner-initiated one) would silently redefine a counter that
  /// already means something narrower on both ends of the wire.
  awaitingCategory,

  /// The surface has NO room, and is waiting on a category AND on the room
  /// becoming optional.
  ///
  /// Analytics practice and the vocab list are not in a room at all. The
  /// decision is that they emit with a null room rather than not emit, but the
  /// wire rejects that today: `room_id` is `min_length=1` on the ingest model and
  /// `NOT NULL` on `dosage_audio_playback`. A synthetic placeholder room is not
  /// an option — it would put a room's worth of fabricated listening into a
  /// per-room table that the serving side buckets and authorizes on.
  awaitingRoomAndCategory,
}

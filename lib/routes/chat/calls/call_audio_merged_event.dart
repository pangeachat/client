import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';

/// The `pangea.call_audio_merged` event: the one full-call recording a single
/// device builds by mixing the two per-device `pangea.call_audio` halves of a
/// sealed, complete 1:1 call, and posts for the whole room to play.
///
/// A sibling of [CallAudioContent] rather than a variant of it -- own relType
/// == event type, exactly [CallAudioContent.relType]'s own convention -- so a
/// reader that only knows the exact type never has to inspect a flag to tell
/// a per-device half from the merged result. This is deliberate: merged
/// events are EXCLUDED from credit, transcription, and per-half totals, and
/// giving them their own type makes that exclusion automatic for every
/// exact-type reader rather than one more condition each has to remember to
/// check.
///
/// Content only, never bytes: like [CallAudioContent], the recording itself
/// lives at [url] on this homeserver's PLAIN (unencrypted) media repository --
/// Pangea's rooms are not end-to-end encrypted, so there is no attached-file
/// key or IV to carry here either.
class CallAudioMergedContent {
  /// The caller's membership event id -- the SAME anchor both source halves
  /// relate to, so a reader that already has one call's key finds the merge
  /// the same way it finds either half.
  final String callKey;

  /// Where the merged recording lives -- an `mxc://` URI from a plain
  /// (unencrypted) upload, on the same terms [CallAudioContent.url] is.
  final String url;

  final String mimetype;

  /// The size of the merged file in bytes, as measured before upload. A
  /// description, not a proof, on the same terms [CallAudioContent.size] is.
  final int size;

  final int durationMs;
  final int sampleRate;

  /// Always 1 for this app's own writer -- the mix is mono -- but carried as
  /// a plain field, not hard-coded, on the same terms [CallAudioContent.channels]
  /// is: a reader still checks it rather than assuming.
  final int channels;

  /// How the uploaded bytes are encoded. This app's own writer always sends
  /// [kCallAudioCodec] (`pcm16`, the mixer's own output format -- see
  /// `call_audio_merge.dart`'s `pcm16ToWav` emit); a reader treats any
  /// non-empty string as usable, exactly [CallAudioContent.codec]'s own rule.
  final String codec;

  /// The earliest source half's `fileStartSfuMs` -- the overlay's own t0 on
  /// the shared SFU clock, the same anchor both source halves were placed
  /// against to build this mix. Nullable and TOLERANT: it only ever improves
  /// alignment DISPLAY, it is never required to identify or play the
  /// recording, on the same terms [CallAudioContent.fileStartSfuMs] treats a
  /// missing half of its own alignment.
  final int? mergedStartSfuMs;

  /// The `pangea.call_audio` event ids this merge mixed -- this merge's own
  /// COVERAGE statement, never the mix's audio content itself. Read through
  /// [canonicalSourceEventIds] everywhere this is used ([toJson],
  /// [coverageHash], [coverageCardinality], [txnId]): the field here holds
  /// whatever the caller constructed this with, but every reader-facing view
  /// of it is sorted and de-duplicated, so two callers who mixed the same two
  /// halves in either order are indistinguishable to a reader.
  ///
  /// This CONSTRUCTOR does not itself refuse an empty or all-unusable list --
  /// it is a plain, non-validating container, on the same terms every other
  /// field here is. Non-empty coverage is guaranteed only for an instance
  /// this reader itself produced, via [fromJson] (which refuses one with no
  /// usable coverage) or `writeCallAudioMergedEvent` (which refuses to send
  /// one) -- never for an instance built directly by some other caller.
  final List<String> sourceEventIds;

  /// Whether the writer mixed EVERY half of the call it names -- both speakers,
  /// every device each used, nothing skipped or cut at the ceiling
  /// (client#9173). Null on a merge written before the field existed; see
  /// `isTrustedWholeMerge` for what such a merge is trusted for.
  final bool? complete;

  const CallAudioMergedContent({
    required this.callKey,
    required this.url,
    required this.mimetype,
    required this.size,
    required this.durationMs,
    required this.sampleRate,
    required this.channels,
    required this.codec,
    this.mergedStartSfuMs,
    required this.sourceEventIds,
    this.complete,
  });

  /// The relation type and the event type are the same string, exactly
  /// [CallAudioContent.relType]'s own convention: this event relates to the
  /// call by being a recording of it, and a second name for that would be one
  /// more thing to keep in step.
  static const relType = 'pangea.call_audio_merged';

  /// Ceilings on untrusted content -- the SAME ones [CallAudioContent] itself
  /// enforces, not merely matching values: a merge is built from two halves
  /// each already under these bounds, so this app's own writer stays under
  /// them the same way the sibling's does, and these only ever bite on
  /// content this app did not write.
  static const maxSize = CallAudioContent.maxSize;
  static const maxDurationMs = CallAudioContent.maxDurationMs;

  /// The most `source_event_ids` this reader will hold from one event.
  ///
  /// Generous rather than tight -- v1 ever mixes exactly two -- because
  /// refusing a genuine future merge (a device-switch call's several halves,
  /// say) over a coverage-count limit is a worse failure than tolerating one
  /// this app would not itself produce today. Exists so a foreign event
  /// cannot hand a reader an unbounded coverage set to hold and compare
  /// against every other merge's own.
  static const maxSourceEventIds = 64;

  /// The most RAW `source_event_ids` entries [_sanitizedSourceEventIds] will
  /// even look at, mirroring `CallTranscriptContent.maxRawEntries`'s own
  /// reasoning: a list of a million duplicates or non-strings must cost this
  /// reader a FIXED amount of work, not a scan proportional to whatever a
  /// hostile event claims to hand it. Four times [maxSourceEventIds] is
  /// generous room for a genuine writer's own duplicates or stray blanks
  /// while still bounding a foreign event's cost.
  static const _maxRawSourceEventIds = 4 * maxSourceEventIds;

  /// The longest single event id [_sanitizedSourceEventIds] will accept into
  /// coverage, on the same terms `CallTranscriptContent.maxDeviceIdChars`
  /// bounds a device id: an id this app's own homeserver mints is a `$` plus
  /// a short opaque token, and this is far more generous than that ever
  /// needs while still bounding how much memory and hashing work one foreign
  /// id can cost.
  static const _maxSourceEventIdChars = 512;

  /// [ids], sorted and de-duplicated, with every empty or MALFORMED string
  /// dropped -- see [_isWellFormedUtf16] for what "malformed" means here and
  /// why it matters to drop it rather than hash it.
  ///
  /// ONE canonicalisation rule, applied everywhere "this merge's coverage"
  /// is asked about -- [toJson], [coverageHash], [coverageCardinality], and
  /// the static [txnId] -- so all four always agree regardless of what order
  /// or how many repeats the caller's own list happened to carry. Never
  /// enforces [maxSourceEventIds] itself: that ceiling is a REFUSAL rule for
  /// untrusted wire content (see [fromJson]), not a property of what
  /// "canonical" means, and applying it here would make an in-memory
  /// instance built by this app's own writer quietly lose coverage it never
  /// asked to lose.
  static List<String> canonicalSourceEventIds(Iterable<String> ids) {
    final unique = <String>{
      for (final id in ids)
        if (id.isNotEmpty && _isWellFormedUtf16(id)) id,
    };
    return List.unmodifiable(unique.toList()..sort());
  }

  /// Whether [s] round-trips through UTF-8 unchanged.
  ///
  /// The cheap, reliable test for "no unpaired UTF-16 surrogate half" --
  /// `utf8.encode` does NOT throw on one (verified against this project's
  /// pinned Dart SDK); it silently SUBSTITUTES the Unicode replacement
  /// character U+FFFD, and every unpaired surrogate substitutes to the SAME
  /// replacement bytes regardless of which one it was. Two DIFFERENT Dart
  /// strings that each contain one -- `String.fromCharCode(0xD800)` and
  /// `String.fromCharCode(0xD801)`, say -- therefore `utf8.encode` to the
  /// IDENTICAL bytes, which would collide in [_hashOf] if either were let
  /// through as a "canonical" id. A real Matrix event id, minted by a
  /// homeserver, never contains one; a malformed id is dropped here, before
  /// it ever reaches the hash, on the same terms any other unusable entry
  /// already is.
  static bool _isWellFormedUtf16(String s) => utf8.decode(utf8.encode(s)) == s;

  /// A stable digest of [canonicalSourceEventIds], hex-encoded.
  ///
  /// SHA-256 over each canonical id, LENGTH-PREFIXED -- each id's own utf8
  /// byte length, then a colon, then the id's own bytes -- rather than joined
  /// by a separator. A separator
  /// assumes no id ever contains it, which a fixed byte cannot promise once
  /// foreign, untrusted `source_event_ids` are in play -- a hostile id
  /// containing that exact byte could make two DIFFERENT coverage sets
  /// serialize to the identical string and collide here; this app's OWN ids
  /// never contain one, but a reader must not rely on senders it does not
  /// control to keep that promise. Length-prefixing has no such assumption to
  /// break: given each segment's own byte length up front, the byte stream
  /// splits back into exactly the original ids no matter what bytes any one
  /// of them contains, so two different id sets can never serialize to the
  /// same bytes.
  ///
  /// Deliberately NOT `hashCode` or `Object.hash`: neither is guaranteed
  /// stable across processes, isolates, or Dart versions -- exactly the
  /// values `txnId` and the player's own dedup (`coverageHash`, read on the
  /// P4 side) both need to agree on FOREVER, across every device that ever
  /// computes them, not merely within one running process.
  static String _hashOf(Iterable<String> ids) {
    final framed = BytesBuilder(copy: false);
    for (final id in canonicalSourceEventIds(ids)) {
      final bytes = utf8.encode(id);
      framed.add(utf8.encode('${bytes.length}:'));
      framed.add(bytes);
    }
    return sha256.convert(framed.toBytes()).toString();
  }

  /// A stable digest of this merge's own coverage. See [_hashOf] for why it
  /// is a content hash rather than a language-level hash, and
  /// [canonicalSourceEventIds] for why the INPUT order of [sourceEventIds]
  /// never changes the result.
  ///
  /// P4's player dedup needs this to rank merged events for the same
  /// [callKey] by coverage before falling back to event id -- see the design
  /// doc's own "Two player rules" -- which this file only computes, never
  /// consumes.
  String get coverageHash => _hashOf(sourceEventIds);

  /// How many DISTINCT source halves this merge covers -- the de-duplicated
  /// count, never the raw [sourceEventIds] length. P4's player dedup ranks
  /// merged events for one call by this first (greatest cardinality wins)
  /// before falling back to [coverageHash] then event id.
  int get coverageCardinality => canonicalSourceEventIds(sourceEventIds).length;

  Map<String, dynamic> toJson() => {
    'call_key': callKey,
    'url': url,
    'mimetype': mimetype,
    'size': size,
    'duration_ms': durationMs,
    'sample_rate': sampleRate,
    'channels': channels,
    'codec': codec,
    'merged_start_sfu_ms': ?mergedStartSfuMs,
    'source_event_ids': canonicalSourceEventIds(sourceEventIds),
    'complete': ?complete,
    'm.relates_to': {'rel_type': relType, 'event_id': callKey},
  };

  /// [raw] sanitised into a coverage list this reader will act on, or null
  /// when there is nothing usable left.
  ///
  /// Tolerant of individual bad entries -- a non-string, empty, malformed, or
  /// over-length element is simply dropped, never a reason to refuse the
  /// whole statement, on the terms every other tolerant field on the sibling
  /// event uses -- but NOT tolerant of the outcomes that make "coverage"
  /// meaningless or unknowable: nothing left after sanitising (a merge with
  /// no coverage says nothing at all), more distinct ids than
  /// [maxSourceEventIds], or a RAW list longer than [_maxRawSourceEventIds]
  /// (all three refused outright rather than silently truncated, because a
  /// shortened coverage set is a DIFFERENT, wrong claim about what this merge
  /// covers, not a smaller true one).
  ///
  /// The raw-length check is why this is bounded work despite refusing
  /// rather than truncating: [List.length] is O(1), so ruling out an
  /// oversized list costs nothing before the loop below ever runs, and the
  /// loop itself is then already bounded by that same ceiling -- unlike
  /// silently scanning only the first [_maxRawSourceEventIds] entries of an
  /// UNBOUNDED list, which would accept whatever coverage that prefix
  /// happened to contain while silently never seeing the rest.
  static List<String>? _sanitizedSourceEventIds(Object? raw) {
    if (raw is! List) return null;
    if (raw.length > _maxRawSourceEventIds) return null;
    final strings = <String>[
      for (final entry in raw)
        if (entry is String && entry.length <= _maxSourceEventIdChars) entry,
    ];
    final canonical = canonicalSourceEventIds(strings);
    if (canonical.isEmpty) return null;
    if (canonical.length > maxSourceEventIds) return null;
    return canonical;
  }

  /// Parses a merged-audio event's content.
  ///
  /// Refuses (returns null) on every field a reader cannot act without: no
  /// call key means nothing to relate this to, no url/mimetype/codec means
  /// nothing playable regardless of what else the event claims, an
  /// out-of-range size or duration means the same untrusted-content ceiling
  /// [CallAudioContent.fromJson] itself enforces, and -- the one rule this
  /// event adds beyond the sibling's own -- empty-or-unbounded
  /// `source_event_ids` means the event states no meaningful coverage at all.
  /// [mergedStartSfuMs] alone is tolerant, on the same terms
  /// [CallAudioContent.clockAnchor] is: a malformed or absent value is simply
  /// null, never a reason to refuse the recording it would only have helped
  /// align.
  static CallAudioMergedContent? fromJson(Map<String, dynamic> content) {
    final callKey = content['call_key'];
    if (callKey is! String || callKey.isEmpty) return null;

    final url = content['url'];
    if (url is! String || url.isEmpty) return null;

    final mimetype = content['mimetype'];
    if (mimetype is! String || mimetype.isEmpty) return null;

    final codec = content['codec'];
    if (codec is! String || codec.isEmpty) return null;

    final size = content['size'];
    if (size is! int || size < 0 || size > maxSize) return null;

    final durationMs = content['duration_ms'];
    if (durationMs is! int || durationMs < 0 || durationMs > maxDurationMs) {
      return null;
    }

    final sampleRate = content['sample_rate'];
    if (sampleRate is! int || sampleRate <= 0) return null;

    final channels = content['channels'];
    if (channels is! int || channels <= 0) return null;

    final sourceEventIds = _sanitizedSourceEventIds(
      content['source_event_ids'],
    );
    if (sourceEventIds == null) return null;

    final mergedStartRaw = content['merged_start_sfu_ms'];

    return CallAudioMergedContent(
      callKey: callKey,
      url: url,
      mimetype: mimetype,
      size: size,
      durationMs: durationMs,
      sampleRate: sampleRate,
      channels: channels,
      codec: codec,
      mergedStartSfuMs: mergedStartRaw is int ? mergedStartRaw : null,
      sourceEventIds: sourceEventIds,
      complete: switch (content['complete']) {
        final bool flag => flag,
        _ => null,
      },
    );
  }

  /// The transaction id for posting this merge.
  ///
  /// Deterministic in `(call_key, coverage-hash)` -- NEVER senderId or
  /// deviceId -- so that any device merging the SAME coverage of the SAME
  /// call produces the SAME transaction id. That is what makes a re-post by
  /// one device collapse server-side (the design doc's own "the
  /// `(call_key, coverage-hash)` txnId collapses a re-post by the same
  /// device"): Matrix's own transaction-id de-duplication (the
  /// `PUT /send/{eventType}/{txnId}` endpoint) is scoped to the SENDING
  /// DEVICE's own session, not merely to the txnId string, so a rare
  /// double-post by two DIFFERENT devices -- even of the SAME account -- still
  /// produces two distinct events, which the player's own dedup -- not this
  /// id -- resolves to one visible row.
  ///
  /// [sourceEventIds] is canonicalised the same way [toJson] and
  /// [coverageHash] are before hashing, so the input order never changes the
  /// result -- see [canonicalSourceEventIds].
  static String txnId(String callKey, List<String> sourceEventIds) =>
      'pangea.call_audio_merged:$callKey:${_hashOf(sourceEventIds)}';
}

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// The codec this app's own writer encodes to. A wire constant rather than a
/// free-form string at the call site, so every half this client writes says
/// the same thing and a reader has exactly one value of its own to recognise.
const kCallAudioCodec = 'pcm16';

/// The `pangea.call_audio` event: one device's own outbound half of one call's
/// audio, uploaded once and referenced here.
///
/// A sibling of [CallTranscriptContent] rather than a field on it. The two are
/// produced on different schedules -- a transcript half is built from
/// segments accumulated across the whole call, an audio half from bytes
/// accumulated across only the stretches THIS device carried the recording --
/// and a merge tool wanting the audio should not have to parse a transcript to
/// find it. Keyed the same way the transcript is (`call_key`, sender, device),
/// so the two halves of one device's contribution are found by the same
/// coordinates.
///
/// One event per DEVICE, never revised. A device that recorded more than one
/// stretch during a call (elected, displaced, re-elected) still writes at most
/// one of these, because [call_audio_recorder.dart]'s ownership lifecycle
/// keeps only the LATEST stretch of carrying alive -- an earlier one that was
/// superseded before the call ended is discarded rather than stitched in. See
/// `CallAudioRecorder` for why: splicing several stretches into one container
/// with the silence between them represented correctly is a materially harder
/// problem than this prototype takes on, and a shorter-but-real half is a
/// safer default than a half that quietly claims to cover stretches it does
/// not.
///
/// Rooms this app creates are unencrypted, so [url] names PLAIN content on the
/// media repository -- there is no attached-file key, IV or hash to carry, and
/// nothing here decrypts anything.
class CallAudioContent {
  /// The caller's membership event id: the same anchor the transcript half
  /// relates to, so a reader that already has one call's key can find both.
  final String callKey;

  /// Which of the sender's devices wrote this half. See
  /// [CallTranscriptContent.deviceId] -- the same rule applies here: absent
  /// means "this writer did not say", never "a different device from the last
  /// one", and every half written by a client that cannot name its own device
  /// keys alike.
  final String? deviceId;

  /// Where the uploaded audio lives -- an `mxc://` URI on this homeserver's
  /// media repository, from a plain (unencrypted) upload. Never a decryption
  /// key or an IV: this app's rooms are not end-to-end encrypted, so nothing
  /// here needs one.
  final String url;

  final String mimetype;

  /// The size of the uploaded file in bytes, as this device measured it before
  /// upload. A description, not a proof -- nothing here re-fetches the blob to
  /// check it.
  final int size;

  final int durationMs;
  final int sampleRate;
  final int channels;

  /// How the uploaded bytes are encoded. See [kCallAudioCodec] for what this
  /// app's own writer sends; a reader treats any non-empty string as usable
  /// and leaves interpreting it to whatever eventually plays the file.
  final String codec;

  /// Where this device's wall clock sat relative to the SFU's, read at join --
  /// the SAME anchor [CallTranscriptContent.clockAnchor] carries, not a second
  /// one measured independently. Reusing it is what lets a merge tool line up
  /// this device's audio against its OWN transcript, and against the other
  /// speaker's, on one shared clock rather than three that might disagree.
  final ClockAnchor? clockAnchor;

  /// How long after this device's own join the recording actually started, on
  /// a MONOTONIC clock -- never a wall-clock subtraction. See
  /// `CallAudioRecorder` for where this is measured and why a monotonic
  /// reading is the one that survives a wall clock correction mid-call.
  ///
  /// Combined with [clockAnchor] via [fileStartSfuMs] to place the first
  /// sample of the uploaded file on the SFU's own clock, the one both
  /// speakers' halves can be compared against.
  final int? recordingStartedOffsetFromDeviceJoinMs;

  const CallAudioContent({
    required this.callKey,
    this.deviceId,
    required this.url,
    required this.mimetype,
    required this.size,
    required this.durationMs,
    required this.sampleRate,
    required this.channels,
    required this.codec,
    this.clockAnchor,
    this.recordingStartedOffsetFromDeviceJoinMs,
  });

  /// The relation type and the event type are the same string, exactly as
  /// [CallTranscriptContent.relType] is: this event relates to the call by
  /// being a recording of it, and a second name for that would be one more
  /// thing to keep in step.
  static const relType = 'pangea.call_audio';

  /// Ceilings on untrusted content, mirroring [CallTranscriptContent.maxSegments]
  /// et al. This client's own writer stays far under both -- the recorder caps
  /// a half at 60 MB and 30 minutes -- so these only ever bite on a half we did
  /// not write. Generous rather than tight: refusing a genuine foreign
  /// recording over a size limit is a worse failure than tolerating one this
  /// app would never itself produce.
  static const maxSize = 200 * 1024 * 1024;
  static const maxDurationMs = 4 * 60 * 60 * 1000;

  /// Where this file's first sample sits on the SFU's own clock, or null when
  /// either half of the alignment is missing.
  ///
  /// BOTH facts or neither, on the same terms [ClockAnchor.fromJson] already
  /// applies to its own two fields: an offset with no anchor beside it
  /// measures nothing, and reading one half as zero would place the file at a
  /// moment the recorder never claimed.
  int? get fileStartSfuMs {
    final anchor = clockAnchor;
    final offset = recordingStartedOffsetFromDeviceJoinMs;
    if (anchor == null || offset == null) return null;
    return anchor.sfuMs + offset;
  }

  Map<String, dynamic> toJson() => {
    'call_key': callKey,
    'device_id': ?CallTranscriptContent.usableDeviceId(deviceId),
    'url': url,
    'mimetype': mimetype,
    'size': size,
    'duration_ms': durationMs,
    'sample_rate': sampleRate,
    'channels': channels,
    'codec': codec,
    'recording_started_offset_from_device_join_ms':
        ?recordingStartedOffsetFromDeviceJoinMs,
    ...?clockAnchor?.toJson(),
    'm.relates_to': {'rel_type': relType, 'event_id': callKey},
  };

  /// Parses an audio event's content.
  ///
  /// Tolerant on the fields that cost only THEMSELVES when they are wrong --
  /// device id, clock anchor, offset -- and refusing on the ones a reader
  /// cannot act without: no call key means nothing to relate this to, and no
  /// url means no audio to offer regardless of what else the event claims.
  static CallAudioContent? fromJson(Map<String, dynamic> content) {
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

    final offsetRaw = content['recording_started_offset_from_device_join_ms'];

    return CallAudioContent(
      callKey: callKey,
      // A malformed device id is ABSENT rather than a reason to refuse the
      // whole half, on the same terms [CallTranscriptContent.deviceId] uses:
      // it decides only how halves are grouped, and refusing the audio to
      // save a grouping would cost the recording to save nothing.
      deviceId: CallTranscriptContent.usableDeviceId(content['device_id']),
      url: url,
      mimetype: mimetype,
      size: size,
      durationMs: durationMs,
      sampleRate: sampleRate,
      channels: channels,
      codec: codec,
      // A malformed anchor is ABSENT, never a reason to reject the half --
      // exactly [CallTranscriptContent]'s own rule, for the same reason: it
      // only ever improves alignment, and the recording is playable without
      // it.
      clockAnchor: ClockAnchor.fromJson(content),
      recordingStartedOffsetFromDeviceJoinMs: offsetRaw is int
          ? offsetRaw
          : null,
    );
  }

  /// The transaction id for sending this half.
  ///
  /// Identical in shape to [CallTranscriptContent.txnId] and for the same
  /// reason: deterministic in (call key, sender, device) so a resend after a
  /// network failure collapses server-side rather than uploading and posting
  /// the recording a second time. See that method for the full argument;
  /// nothing here differs but the event name in the prefix.
  static String txnId(String callKey, String senderId, String? deviceId) =>
      'pangea.call_audio:$callKey:$senderId:'
      '${CallTranscriptContent.usableDeviceId(deviceId) ?? ''}';
}

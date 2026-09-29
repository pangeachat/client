import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_download.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_provenance.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/whole_call_transcriber.dart';

// The two members of the 1:1 DM, the call anchor, and the peer's one recording.
const _self = '@self:server';
const _peer = '@peer:server';
const _callKey = '\$call:server';
const _peerDevice = 'PEERDEVICE';
const _peerAudioId = '\$audio_peer:server';

TranscriptSegment _seg(String text, [int atMs = 1000]) =>
    TranscriptSegment(text, atMs: atMs);

CallAudioContent _content({
  String? deviceId = _peerDevice,
  String url = 'mxc://server/peeraudio',
  int durationMs = 5000,
  int sampleRate = 16000,
  int channels = 1,
  ClockAnchor? clockAnchor,
  int? offset,
}) => CallAudioContent(
  callKey: _callKey,
  deviceId: deviceId,
  url: url,
  mimetype: 'audio/wav',
  size: 1000,
  durationMs: durationMs,
  sampleRate: sampleRate,
  channels: channels,
  codec: 'pcm16',
  clockAnchor: clockAnchor,
  recordingStartedOffsetFromDeviceJoinMs: offset,
);

CallAudioRecording _rec({
  String eventId = _peerAudioId,
  String senderId = _peer,
  CallAudioContent? content,
}) => CallAudioRecording(
  eventId: eventId,
  senderId: senderId,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
  content: content ?? _content(),
);

CallAudioMergedRecording _manifest({
  required String eventId,
  required List<String> sourceEventIds,
  String sender = _peer,
  int ts = 1000,
}) => CallAudioMergedRecording(
  eventId: eventId,
  senderId: sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
  content: CallAudioMergedContent(
    callKey: _callKey,
    url: 'mxc://server/merged',
    mimetype: 'audio/wav',
    size: 2000,
    durationMs: 8000,
    sampleRate: 16000,
    channels: 1,
    codec: 'pcm16',
    sourceEventIds: sourceEventIds,
  ),
);

/// A memoized-free fake resolver over a fixed table: a served id validates, an
/// id in [pending] throws-equivalent (transient), any other id is gone.
AudioResolver _fakeResolver(
  Map<String, AudioResolution> serve, {
  Set<String> pending = const {},
}) => (id) async {
  if (pending.contains(id)) return const AudioResolution.pending();
  return serve[id] ?? const AudioResolution.gone();
};

/// A real assembled transcript for the skip check. [peerAuthentic] adds the
/// peer's own half (no `spokenBy`); [peerValidBackfill] adds a VALID peer half
/// written by [_self]; otherwise the peer is absent (a half should be produced).
CallTranscript _transcript({
  bool peerAuthentic = false,
  bool peerValidBackfill = false,
}) {
  final candidates = <TranscriptCandidate>[];
  final provenance = <String, ProvenanceState>{};
  if (peerAuthentic) {
    candidates.add(
      TranscriptCandidate(
        senderId: _peer,
        eventId: '\$t_peer_auth',
        deviceId: _peerDevice,
        originServerTs: 2000,
        segments: [_seg('peer said this')],
        accounting: const HalfAccounting(),
      ),
    );
  }
  if (peerValidBackfill) {
    candidates.add(
      TranscriptCandidate(
        senderId: _self,
        eventId: '\$t_peer_backfill',
        deviceId: _peerDevice,
        spokenBy: _peer,
        sourceAudioEventId: _peerAudioId,
        originServerTs: 3000,
        segments: [_seg('backfilled peer speech')],
        accounting: const HalfAccounting(),
      ),
    );
    provenance['\$t_peer_backfill'] = ProvenanceState.valid;
  }
  return assembleTranscript(
    candidates: candidates,
    expectedSenders: const [_self, _peer],
    provenance: provenance,
  );
}

/// One posted peer half, captured for assertions.
class _Posted {
  final String callKey;
  final String spokenBy;
  final String sourceAudioEventId;
  final String? deviceId;
  final String? langCode;
  final ClockAnchor? clockAnchor;
  final List<TranscriptSegment> segments;
  _Posted(
    this.callKey,
    this.spokenBy,
    this.sourceAudioEventId,
    this.deviceId,
    this.langCode,
    this.clockAnchor,
    this.segments,
  );
}

/// A configurable harness: every seam defaults to the common "one subscribed
/// invoker, peer absent, everything resolves" case and records its calls.
class _Harness {
  final List<String> log = [];
  final List<Duration> waits = [];
  final List<_Posted> posts = [];
  int transcribeCalls = 0;
  int discoverCalls = 0;
  int readCalls = 0;
  final List<({String? l1, String? l2})> transcribeLangs = [];
  final List<int> transcribeStarts = [];

  bool enabled = true;
  String selfUserId = _self;
  Set<String> participants = const {_self, _peer};

  ManifestDiscoverer? discover;
  TranscriptReader? readTranscript;
  CallAudioDownloader? download;
  RecordingTranscriber? transcribe;
  PeerLanguageResolver? resolvePeerLanguages;
  Future<void> Function(Duration)? wait;
  int maxManifestRetries = 4;

  WholeCallTranscriber build() => WholeCallTranscriber(
    selfUserId: selfUserId,
    participants: participants,
    isEnabled: () => enabled,
    discover:
        discover ??
        (_) async {
          discoverCalls++;
          log.add('discover');
          return WholeCallManifest(resolved: true, recordings: [_rec()]);
        },
    readTranscript:
        readTranscript ??
        (_) async {
          readCalls++;
          log.add('read');
          return _transcript();
        },
    download:
        download ??
        (_) async {
          log.add('download');
          return Uint8List.fromList(const [1, 2, 3, 4]);
        },
    transcribe:
        transcribe ??
        (
          bytes, {
          required String l1,
          required String l2,
          required int startedAtMs,
          required int durationMs,
        }) async {
          transcribeCalls++;
          transcribeLangs.add((l1: l1, l2: l2));
          transcribeStarts.add(startedAtMs);
          log.add('transcribe');
          return [_seg('hola', startedAtMs)];
        },
    resolvePeerLanguages:
        resolvePeerLanguages ?? (_) async => (l1: 'en', l2: 'es'),
    post:
        ({
          required String callKey,
          required String spokenBy,
          required String sourceAudioEventId,
          required String? deviceId,
          required String? langCode,
          required ClockAnchor? clockAnchor,
          required List<TranscriptSegment> segments,
        }) async {
          log.add('post');
          posts.add(
            _Posted(
              callKey,
              spokenBy,
              sourceAudioEventId,
              deviceId,
              langCode,
              clockAnchor,
              segments,
            ),
          );
        },
    wait:
        wait ??
        (d) async {
          waits.add(d);
          log.add('wait');
        },
    jitter: () => 0.0,
    maxManifestRetries: maxManifestRetries,
  );
}

void main() {
  group('gating', () {
    test('disabled (flag off or unsubscribed) produces nothing', () async {
      // Mutation proof: dropping the run-time gate makes a disabled call wait the
      // grace and discover -- so the wait/discover assertions redden.
      final h = _Harness()..enabled = false;
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.waits, isEmpty); // not even the grace is waited when disabled
      expect(h.discoverCalls, 0);
      expect(h.transcribeCalls, 0);
      expect(h.posts, isEmpty);
    });

    test('enabled backfills the absent peer half', () async {
      final h = _Harness();
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.posts, hasLength(1));
    });

    test('an unknown self (empty user id) produces nothing', () async {
      // A half is signed by the writer and keyed by a txn lane that must never
      // be empty. Mutation proof: dropping the `_identityKnown` guard runs
      // discovery and posts a half with an empty writer.
      final h = _Harness()
        ..selfUserId = ''
        ..participants = const {'', _peer};
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.discoverCalls, 0);
      expect(h.posts, isEmpty);
      final onDemand = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(onDemand, OnDemandTranscriptionResult.disabled);
    });

    test(
      'a participant set that is not exactly two produces nothing',
      () async {
        // Not a resolvable 1:1 DM (peer unknown), so no unit and no spokenBy.
        final h = _Harness()..participants = const {_self};
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.discoverCalls, 0);
        expect(h.posts, isEmpty);
      },
    );
  });

  group('skip predicates', () {
    test('an AUTHENTIC peer half already present is not re-produced', () async {
      // Mutation proof: dropping the `_skip` guard produces a duplicate half.
      final h = _Harness()
        ..readTranscript = (_) async => _transcript(peerAuthentic: true);
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.transcribeCalls, 0);
      expect(h.posts, isEmpty);
    });

    test(
      'a VALID peer-produced half already present is not re-produced',
      () async {
        // Mutation proof: dropping the `_skip` guard re-transcribes and re-posts.
        final h = _Harness()
          ..readTranscript = (_) async => _transcript(peerValidBackfill: true);
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.transcribeCalls, 0);
        expect(h.posts, isEmpty);
      },
    );
  });

  group('call-end sequencing', () {
    test(
      'own-first (precondition) -> grace -> re-read -> backfill, in order',
      () async {
        // Mutation proof: removing the leading `await wait(grace)` drops the first
        // 'wait' and the order no longer starts grace-before-discover.
        final h = _Harness();
        await h.build().transcribeAtCallEnd(_callKey);
        // grace -> discover -> backfill-gate read -> pre-STT re-check read ->
        // download -> transcribe -> pre-send re-check read -> post.
        expect(h.log, [
          'wait',
          'discover',
          'read',
          'read',
          'download',
          'transcribe',
          'read',
          'post',
        ]);
        // The grace was waited before any discovery.
        expect(h.waits.first, const Duration(seconds: 3));
      },
    );

    test(
      'both subscribed: peer authentic on re-read -> no cross-transcription',
      () async {
        // Each side posts its OWN half; this invoker re-reads, sees the peer's
        // authentic half, and does NOT transcribe the peer's audio. Zero duplicate
        // speech-to-text. Mutation proof: dropping `_skip` transcribes the peer.
        final h = _Harness()
          ..readTranscript = (_) async => _transcript(peerAuthentic: true);
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.transcribeCalls, 0);
        expect(h.posts, isEmpty);
      },
    );
  });

  group('mixed case (the acceptance path)', () {
    test(
      'subscriber backfills the peer half in the SPEAKER\'s language',
      () async {
        final h = _Harness()
          ..resolvePeerLanguages = (id) async {
            expect(id, _peer);
            return (l1: 'fr', l2: 'de'); // the PEER's pair, not the invoker's
          };
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.transcribeCalls, 1);
        // Transcribed in the speaker's own pair.
        expect(h.transcribeLangs.single, (l1: 'fr', l2: 'de'));
        expect(h.posts, hasLength(1));
      },
    );

    test(
      'posted half carries spokenBy / sourceAudioEventId / deviceId / langCode',
      () async {
        const anchor = ClockAnchor(sfuMs: 100000, deviceMs: 100050);
        final h = _Harness();
        h.discover = (_) async => WholeCallManifest(
          resolved: true,
          recordings: [
            _rec(content: _content(clockAnchor: anchor, offset: 250)),
          ],
        );
        h.resolvePeerLanguages = (_) async => (l1: 'en', l2: 'es');
        await h.build().transcribeAtCallEnd(_callKey);
        final posted = h.posts.single;
        expect(posted.spokenBy, _peer);
        expect(posted.sourceAudioEventId, _peerAudioId);
        expect(posted.deviceId, _peerDevice);
        expect(posted.langCode, 'es'); // the target language used
        expect(posted.callKey, _callKey);
        // The peer's own anchor is carried, and the segments are placed on the
        // peer's device clock (deviceMs + offset).
        expect(posted.clockAnchor, anchor);
        expect(h.transcribeStarts.single, 100050 + 250);
      },
    );

    test(
      'an UNANCHORED peer recording starts on the wall clock, not epoch',
      () async {
        // No clockAnchor and no offset, so the peer's device clock is unknown.
        // The start must fall back to the recording event's WALL clock (its
        // server-receive time less its duration), not 0/epoch -- otherwise
        // every unanchored peer turn is stamped at ~1970 and sorts before all
        // of the invoker's own turns.
        // Mutation proof: restoring `return 0` makes the start 0 here -> RED.
        final h = _Harness();
        h.discover = (_) async => WholeCallManifest(
          resolved: true,
          recordings: [
            CallAudioRecording(
              eventId: _peerAudioId,
              senderId: _peer,
              // 100_000ms since epoch, a 5_000ms recording -> began at 95_000.
              originServerTs: DateTime.fromMillisecondsSinceEpoch(100000),
              content: _content(durationMs: 5000),
            ),
          ],
        );
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.transcribeStarts.single, 95000);
      },
    );
  });

  group('language gate', () {
    test('an unresolved peer language does NOT auto-produce', () async {
      // Mutation proof: a silent fallback (e.g. l2 ??= 'es') would post a half.
      final h = _Harness()
        ..resolvePeerLanguages = (_) async => (l1: null, l2: null);
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.transcribeCalls, 0);
      expect(h.posts, isEmpty);
    });

    test('a resolved base but missing target does NOT auto-produce', () async {
      final h = _Harness()
        ..resolvePeerLanguages = (_) async => (l1: 'en', l2: null);
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.posts, isEmpty);
    });
  });

  group('merge-arrival retry', () {
    test(
      'produces the peer half when the manifest arrives on a later attempt',
      () async {
        // Mutation proof: removing the retry loop leaves the first (unresolved)
        // discovery final, and the peer half is never produced.
        var attempt = 0;
        final h = _Harness();
        h.discover = (_) async {
          attempt++;
          if (attempt < 3) return WholeCallManifest.absent; // merge not visible
          return WholeCallManifest(resolved: true, recordings: [_rec()]);
        };
        await h.build().transcribeAtCallEnd(_callKey);
        expect(attempt, 3);
        expect(h.posts, hasLength(1));
      },
    );

    test(
      'gives up after the bounded retries when no manifest ever arrives',
      () async {
        var discoveries = 0;
        final h = _Harness();
        h.maxManifestRetries = 2;
        h.discover = (_) async {
          discoveries++;
          return WholeCallManifest.absent;
        };
        await h.build().transcribeAtCallEnd(_callKey);
        // Initial attempt + 2 retries = 3 discoveries, then it stops.
        expect(discoveries, 3);
        expect(h.posts, isEmpty);
      },
    );
  });

  group('in-flight guard and re-checks', () {
    test('concurrent runs transcribe one device only once', () async {
      // A gated transcribe lets both runs reach the STT step; the in-flight lock
      // keyed by the recording device admits only one. Mutation proof: removing
      // the `_inFlight` guard transcribes and posts twice.
      final gate = Completer<void>();
      final h = _Harness();
      h.transcribe =
          (
            bytes, {
            required String l1,
            required String l2,
            required int startedAtMs,
            required int durationMs,
          }) async {
            h.transcribeCalls++;
            await gate.future;
            return [_seg('hola', startedAtMs)];
          };
      final t = h.build();
      final a = t.transcribeAtCallEnd(_callKey);
      final b = t.transcribeAtCallEnd(_callKey);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([a, b]);
      expect(h.transcribeCalls, 1);
      expect(h.posts, hasLength(1));
    });

    test(
      'a half that lands during STT is not doubled (re-check before send)',
      () async {
        // The first read (backfill gate) sees the peer absent; by the send re-check
        // the peer's authentic half has landed, so nothing is posted. Mutation
        // proof: removing the pre-send re-check posts a duplicate.
        var reads = 0;
        final h = _Harness()
          ..readTranscript = (_) async {
            reads++;
            // Absent for the first two reads (backfill gate + pre-STT re-check),
            // present by the pre-send re-check.
            return _transcript(peerAuthentic: reads >= 3);
          };
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.transcribeCalls, 1); // STT ran (pre-STT read still absent)
        expect(h.posts, isEmpty); // but the send was withheld
      },
    );
  });

  group('bytes and empty results', () {
    test('a recording whose bytes cannot be downloaded is skipped', () async {
      final h = _Harness()..download = (_) async => throw StateError('gone');
      await h.build().transcribeAtCallEnd(_callKey);
      expect(h.posts, isEmpty);
    });

    test(
      'an empty transcription is not posted as "the peer said nothing"',
      () async {
        final h = _Harness();
        h.transcribe =
            (
              bytes, {
              required String l1,
              required String l2,
              required int startedAtMs,
              required int durationMs,
            }) async {
              h.transcribeCalls++;
              return const [];
            };
        await h.build().transcribeAtCallEnd(_callKey);
        expect(h.transcribeCalls, 1);
        expect(h.posts, isEmpty);
      },
    );
  });

  group('on-demand entry', () {
    test('transcribes one named half now, with no grace', () async {
      final h = _Harness();
      final produced = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(produced, OnDemandTranscriptionResult.produced);
      expect(h.waits, isEmpty); // no grace on the on-demand path
      expect(h.posts, hasLength(1));
    });

    test(
      'uses the picker language when the peer language did not resolve',
      () async {
        final h = _Harness()
          ..resolvePeerLanguages = (_) async => (l1: null, l2: null);
        final produced = await h.build().transcribeHalfOnDemand(
          callKey: _callKey,
          speakerId: _peer,
          language: 'es',
        );
        expect(produced, OnDemandTranscriptionResult.produced);
        expect(h.posts.single.langCode, 'es');
      },
    );

    test('produces nothing for a speaker with no manifest recording', () async {
      final h = _Harness()
        ..discover = (_) async =>
            const WholeCallManifest(resolved: true, recordings: []);
      final produced = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(produced, OnDemandTranscriptionResult.noRecording);
      expect(h.posts, isEmpty);
    });
  });

  group('on-demand result mapping (#8792 task 3)', () {
    // Each outcome is a DISTINCT reason a request did not post a half; the view
    // marks a half "audio unavailable" only for `audioUnavailable` and leaves
    // the rest retryable. Group mutation proof: collapsing the typed result
    // back to a bool (every non-produced reason -> one value) makes the
    // disabled / manifestPending / noRecording / alreadyPresent expectations
    // below indistinguishable from audioUnavailable -> RED.
    test('disabled when the run-time gate is not satisfied', () async {
      final h = _Harness()..enabled = false;
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.disabled);
      expect(h.posts, isEmpty);
    });

    test('manifestPending when no manifest is visible yet', () async {
      final h = _Harness()..discover = (_) async => WholeCallManifest.absent;
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.manifestPending);
      expect(h.posts, isEmpty);
    });

    test('noRecording when the manifest names none for the speaker', () async {
      final h = _Harness()
        ..discover = (_) async =>
            const WholeCallManifest(resolved: true, recordings: []);
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.noRecording);
      expect(h.posts, isEmpty);
    });

    test('alreadyPresent when a half for the speaker already exists', () async {
      final h = _Harness()
        ..readTranscript = (_) async => _transcript(peerAuthentic: true);
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.alreadyPresent);
      expect(h.posts, isEmpty);
    });

    test('audioUnavailable when the downloaded bytes are empty', () async {
      final h = _Harness()..download = (_) async => Uint8List(0);
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.audioUnavailable);
      expect(h.posts, isEmpty);
    });

    test('audioUnavailable when speech-to-text yields nothing', () async {
      final h = _Harness()
        ..transcribe =
            (
              bytes, {
              required String l1,
              required String l2,
              required int startedAtMs,
              required int durationMs,
            }) async => const <TranscriptSegment>[];
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.audioUnavailable);
      expect(h.posts, isEmpty);
    });

    test('produced when a half is transcribed and posted', () async {
      final h = _Harness();
      final result = await h.build().transcribeHalfOnDemand(
        callKey: _callKey,
        speakerId: _peer,
      );
      expect(result, OnDemandTranscriptionResult.produced);
      expect(h.posts, hasLength(1));
    });
  });

  // Discovery selects the manifest through the SAME shared function the reader
  // uses (proven at the unit level in transcript_provenance_test.dart); these
  // cover the producer's use of it and its transient handling.
  group('discoverWholeCallManifest', () {
    // A validated resolution carries senderId + content + originServerTs, so a
    // recording is built from it directly -- no second fetch.
    AudioResolution validated(String device, [int ts = 1000]) =>
        AudioResolution.resolved(
          _peer,
          _content(deviceId: device),
          DateTime.fromMillisecondsSinceEpoch(ts),
        );

    test(
      'selects the reader-order winner on a coverage tie, not list order',
      () async {
        // Two equal-coverage manifests; the earlier-ts one wins the shared total
        // order, so the recording returned is ITS source, not the first in list.
        final manifest = await discoverWholeCallManifest(
          mergedRecordings: [
            _manifest(
              eventId: '\$mLate',
              sourceEventIds: ['\$srcLate'],
              ts: 2000,
            ),
            _manifest(
              eventId: '\$mEarly',
              sourceEventIds: ['\$srcEarly'],
              ts: 1000,
            ),
          ],
          participants: const {_self, _peer},
          callKey: _callKey,
          resolve: _fakeResolver({
            '\$srcLate': validated('devLate'),
            '\$srcEarly': validated('devEarly'),
          }),
        );
        expect(manifest.resolved, isTrue);
        expect(manifest.recordings.single.eventId, '\$srcEarly');
      },
    );

    test(
      'every source the selection validated is present in the recordings',
      () async {
        // Recordings are built from the SAME memoized resolutions that validated
        // the sources, so a manifest whose two sources both validate yields BOTH.
        // Mutation proof: building via a second, separately-failing fetch (the
        // old design) could return null for a validated source and drop it here
        // while `resolved` stayed true -- this asserts both are present.
        final manifest = await discoverWholeCallManifest(
          mergedRecordings: [
            _manifest(eventId: '\$m1', sourceEventIds: ['\$srcA', '\$srcB']),
          ],
          participants: const {_self, _peer},
          callKey: _callKey,
          resolve: _fakeResolver({
            '\$srcA': validated('devA'),
            '\$srcB': validated('devB'),
          }),
        );
        expect(manifest.resolved, isTrue);
        expect(manifest.recordings.map((r) => r.eventId).toSet(), {
          '\$srcA',
          '\$srcB',
        });
      },
    );

    test(
      'returns not-resolved on an uncertain (transient) selection',
      () async {
        // A validation fetch is transient, so the selection is uncertain and an
        // alternate may have been chosen -- return absent so the retry re-runs.
        // Mutation proof: dropping the `|| selection.uncertain` guard returns
        // RESOLVED with the alternate manifest here.
        final manifest = await discoverWholeCallManifest(
          mergedRecordings: [
            _manifest(eventId: '\$mOk', sourceEventIds: ['\$srcOk']),
            _manifest(eventId: '\$mPending', sourceEventIds: ['\$srcPending']),
          ],
          participants: const {_self, _peer},
          callKey: _callKey,
          resolve: _fakeResolver(
            {'\$srcOk': validated('devOk')},
            pending: {'\$srcPending'},
          ),
        );
        expect(manifest.resolved, isFalse);
        expect(manifest.recordings, isEmpty);
      },
    );
  });
}

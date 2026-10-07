import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_provenance.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

const _room = '!room:example.com';
const _callKey = '\$membership:example.com';
const alice = '@alice:example.com';
const bob = '@bob:example.com';
const carol = '@carol:example.com';

CallAudioContent _audio({
  String callKey = _callKey,
  String? deviceId = 'devA',
}) => CallAudioContent(
  callKey: callKey,
  deviceId: deviceId,
  url: 'mxc://example.com/audio',
  mimetype: 'audio/wav',
  size: 1000,
  durationMs: 5000,
  sampleRate: 16000,
  channels: 1,
  codec: kCallAudioCodec,
  // Placeable, as every recording a merge is made from is.
  clockAnchor: const ClockAnchor(sfuMs: 1000, deviceMs: 1000),
  recordingStartedOffsetFromDeviceJoinMs: 0,
);

/// Bob's own recording of the call: with an alice recording, the WHOLE call a
/// trusted manifest covers (client#9173).
const _audioB = '\$audioB';
final _bobServed = {
  _audioB: FetchedAudioEvent(
    senderId: bob,
    content: _audio(deviceId: 'devB'),
  ),
};

CallAudioMergedRecording _manifest({
  required String eventId,
  required String sender,
  required List<String> sourceEventIds,
  String callKey = _callKey,
  int ts = 1000,
}) => CallAudioMergedRecording(
  eventId: eventId,
  senderId: sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
  content: CallAudioMergedContent(
    callKey: callKey,
    url: 'mxc://example.com/merged',
    mimetype: 'audio/wav',
    size: 2000,
    durationMs: 8000,
    sampleRate: 16000,
    channels: 1,
    codec: kCallAudioCodec,
    sourceEventIds: sourceEventIds,
    // A trusted merge of the whole call: starting where its halves start and
    // saying it mixed all of them.
    mergedStartSfuMs: 1000,
    complete: true,
  ),
);

TranscriptCandidate _peer({
  required String writer,
  required String spokenBy,
  required String eventId,
  required String? sourceAudioEventId,
  String? device = 'devA',
  int ts = 1000,
}) => TranscriptCandidate(
  senderId: writer,
  eventId: eventId,
  spokenBy: spokenBy,
  sourceAudioEventId: sourceAudioEventId,
  deviceId: device,
  originServerTs: ts,
  segments: const [],
  accounting: const HalfAccounting(
    chunksCaptured: 1,
    chunksTranscribed: 1,
    declared: true,
  ),
);

/// A fetcher serving a fixed table by event id and recording every call.
///
/// An entry mapped to a [FetchedAudioEvent] is that event; an id in [gone]
/// resolves to null (not on the server); an id in [throwing] fails the fetch
/// (transient). An id in none of the three also resolves to null.
class _Fetcher {
  final Map<String, FetchedAudioEvent> serve;
  final Set<String> gone;
  final Set<String> throwing;
  final List<String> calls = [];

  _Fetcher({
    this.serve = const {},
    this.gone = const {},
    this.throwing = const {},
  });

  AudioEventFetcher get fetch =>
      ({required String roomId, required String eventId}) async {
        // Asserted, not ignored: a fetcher answering whatever it is asked would
        // let the resolver query the wrong room and still pass.
        expect(roomId, _room);
        calls.add(eventId);
        if (throwing.contains(eventId)) throw Exception('transient');
        if (gone.contains(eventId)) return null;
        return serve[eventId];
      };
}

Future<Map<String, ProvenanceState>> _resolve({
  required List<TranscriptCandidate> candidates,
  required List<CallAudioMergedRecording> mergedRecordings,
  required _Fetcher fetcher,
  Set<String> participants = const {alice, bob},
}) => resolveTranscriptProvenance(
  candidates: candidates,
  mergedRecordings: mergedRecordings,
  participants: participants,
  callKey: _callKey,
  roomId: _room,
  fetch: fetcher.fetch,
);

void main() {
  group('resolveTranscriptProvenance', () {
    test(
      'a claim in the manifest, resolving to the speaker\'s own audio, is VALID',
      () async {
        final fetcher = _Fetcher(
          serve: {
            '\$audioA': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devA'),
            ),
            ..._bobServed,
          },
        );
        final states = await _resolve(
          candidates: [
            _peer(
              writer: bob,
              spokenBy: alice,
              eventId: '\$t1',
              sourceAudioEventId: '\$audioA',
              device: 'devA',
            ),
          ],
          mergedRecordings: [
            _manifest(
              eventId: '\$m1',
              sender: bob,
              sourceEventIds: ['\$audioA', _audioB],
            ),
          ],
          fetcher: fetcher,
        );
        expect(states['\$t1'], ProvenanceState.valid);
      },
    );

    test('a device MISMATCH makes an otherwise-valid claim INVALID', () async {
      // The source audio's device is devB; the half is keyed by devA. Honouring
      // it would attribute one device's recording to another's half.
      final fetcher = _Fetcher(
        serve: {
          '\$audioA': FetchedAudioEvent(
            senderId: alice,
            content: _audio(deviceId: 'devB'),
          ),
          ..._bobServed,
        },
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioA',
            device: 'devA',
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioA', _audioB],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.invalidTerminal);
    });

    test('a source that resolves to the WRONG sender is INVALID', () async {
      // Resolves to bob's audio, but the half claims alice spoke it.
      final fetcher = _Fetcher(
        serve: {
          '\$audioA': FetchedAudioEvent(senderId: bob, content: _audio()),
          '\$audioAlice': FetchedAudioEvent(
            senderId: alice,
            content: _audio(deviceId: 'devAlice'),
          ),
        },
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioA',
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioA', '\$audioAlice'],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.invalidTerminal);
    });

    test('a spokenBy that is not a participant is INVALID', () async {
      // The manifest is genuine (a real alice source validates it), so it IS
      // selected -- which is what lets this test isolate the participant check:
      // without it, the carol source would resolve, match, and read VALID.
      final fetcher = _Fetcher(
        serve: {
          '\$audioAlice': FetchedAudioEvent(
            senderId: alice,
            content: _audio(deviceId: 'devAlice'),
          ),
          '\$audioCarol': FetchedAudioEvent(
            senderId: carol,
            content: _audio(deviceId: 'devA'),
          ),
        },
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: carol,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioCarol',
            device: 'devA',
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioAlice', '\$audioCarol'],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.invalidTerminal);
    });

    test(
      'a source NOT in the selected manifest is INVALID, with no fetch of it',
      () async {
        // The real manifest lists only the real source. A flood half references a
        // genuine alice recording that was never merged.
        final fetcher = _Fetcher(
          serve: {
            '\$audioReal': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devA'),
            ),
            '\$audioLoose': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devB'),
            ),
            ..._bobServed,
          },
        );
        final states = await _resolve(
          candidates: [
            _peer(
              writer: bob,
              spokenBy: alice,
              eventId: '\$t1',
              sourceAudioEventId: '\$audioLoose',
              device: 'devB',
            ),
          ],
          mergedRecordings: [
            _manifest(
              eventId: '\$m1',
              sender: bob,
              sourceEventIds: ['\$audioReal', _audioB],
            ),
          ],
          fetcher: fetcher,
        );
        expect(states['\$t1'], ProvenanceState.invalidTerminal);
        expect(
          fetcher.calls,
          isNot(contains('\$audioLoose')),
          reason:
              'a non-manifest source is rejected by set membership, not fetched',
        );
      },
    );

    // client#9173: a merge is trusted only when EVERY source it lists is a
    // participant's recording of this call, so one listing a source that is
    // gone is never the manifest -- the claim waits rather than resolving
    // against a merge that cannot be the whole call.
    test('a manifest listing a redacted source is not trusted: the claim stays '
        'PENDING, never the writer', () async {
      final fetcher = _Fetcher(
        serve: {
          '\$audioReal': FetchedAudioEvent(senderId: alice, content: _audio()),
          '\$audioGone': FetchedAudioEvent(senderId: alice, redacted: true),
          ..._bobServed,
        },
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioGone',
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioReal', '\$audioGone', _audioB],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.pendingTransient);
    });

    test('a manifest listing a source that is not found is not trusted: the '
        'claim stays PENDING', () async {
      final fetcher = _Fetcher(
        serve: {
          '\$audioReal': FetchedAudioEvent(senderId: alice, content: _audio()),
          ..._bobServed,
        },
        gone: {'\$audioGone'},
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioGone',
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioReal', '\$audioGone', _audioB],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.pendingTransient);
    });

    test('a transient fetch failure is PENDING (retryable)', () async {
      final fetcher = _Fetcher(
        serve: {
          '\$audioReal': FetchedAudioEvent(senderId: alice, content: _audio()),
        },
        throwing: {'\$audioFlaky'},
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioFlaky',
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioReal', '\$audioFlaky'],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.pendingTransient);
    });

    test('no manifest yet -> PENDING, never the writer', () async {
      final fetcher = _Fetcher();
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioA',
          ),
        ],
        mergedRecordings: const [],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.pendingTransient);
    });

    test(
      'a manifest that validates nothing is treated as no manifest (PENDING)',
      () async {
        // 64 bogus ids, none resolving to a real recording. It must not become
        // "the manifest" and force real claims into a not-in-manifest reject.
        final bogus = [for (var i = 0; i < 64; i++) '\$bogus$i'];
        final fetcher = _Fetcher(); // every id resolves to null (gone)
        final states = await _resolve(
          candidates: [
            _peer(
              writer: bob,
              spokenBy: alice,
              eventId: '\$t1',
              sourceAudioEventId: '\$audioReal',
            ),
          ],
          mergedRecordings: [
            _manifest(eventId: '\$mBogus', sender: bob, sourceEventIds: bogus),
          ],
          fetcher: fetcher,
        );
        expect(states['\$t1'], ProvenanceState.pendingTransient);
      },
    );

    test('a malformed peer half (no source id) is INVALID', () async {
      final fetcher = _Fetcher(
        serve: {
          '\$audioReal': FetchedAudioEvent(senderId: alice, content: _audio()),
        },
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: null,
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioReal'],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.invalidTerminal);
    });

    test(
      'an authentic-only read resolves to an empty map (no fetch)',
      () async {
        final fetcher = _Fetcher();
        final states = await _resolve(
          candidates: [
            TranscriptCandidate(
              senderId: alice,
              eventId: '\$a1',
              originServerTs: 1000,
              segments: const [],
              accounting: const HalfAccounting(declared: true),
            ),
          ],
          mergedRecordings: [
            _manifest(
              eventId: '\$m1',
              sender: bob,
              sourceEventIds: ['\$audioA'],
            ),
          ],
          fetcher: fetcher,
        );
        expect(states, isEmpty);
        expect(
          fetcher.calls,
          isEmpty,
          reason: 'no peer claim, so no manifest read',
        );
      },
    );

    test('a device-LESS half is INVALID even against its speaker\'s own '
        'audio in the manifest', () async {
      // The source resolves to the named speaker's own audio for this call, in
      // a trusted manifest, but the half names no device. A unit is (call,
      // speaker, device): a half that cannot say which device's recording it
      // is never binds to one. (A device-less SOURCE can never be in a trusted
      // manifest at all since client#9173.)
      final fetcher = _Fetcher(
        serve: {
          '\$audioReal': FetchedAudioEvent(
            senderId: alice,
            content: _audio(deviceId: 'devReal'),
          ),
          ..._bobServed,
        },
      );
      final states = await _resolve(
        candidates: [
          _peer(
            writer: bob,
            spokenBy: alice,
            eventId: '\$t1',
            sourceAudioEventId: '\$audioReal',
            device: null,
          ),
        ],
        mergedRecordings: [
          _manifest(
            eventId: '\$m1',
            sender: bob,
            sourceEventIds: ['\$audioReal', _audioB],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.invalidTerminal);
    });

    test(
      'a transient validation miss holds a real half PENDING, not INVALID',
      () async {
        // Two participant-authored manifests. The FAKE one validates (its source
        // resolves); the REAL one's only source fetch THROWS, so it is
        // undercounted and the fake one is selected. A peer half whose source is
        // only in the real manifest must not be terminally rejected on that
        // transient miss -- a rebuild re-fetches and selects the real manifest.
        final fetcher = _Fetcher(
          serve: {
            '\$audioFake': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devFake'),
            ),
          },
          throwing: {'\$audioRealPending'},
        );
        final states = await _resolve(
          candidates: [
            _peer(
              writer: bob,
              spokenBy: alice,
              eventId: '\$t1',
              sourceAudioEventId: '\$audioRealPending',
              device: 'devA',
            ),
          ],
          mergedRecordings: [
            _manifest(
              eventId: '\$mFake',
              sender: bob,
              sourceEventIds: ['\$audioFake'],
            ),
            _manifest(
              eventId: '\$mReal',
              sender: bob,
              sourceEventIds: ['\$audioRealPending'],
            ),
          ],
          fetcher: fetcher,
        );
        expect(states['\$t1'], ProvenanceState.pendingTransient);
      },
    );

    group('manifest selection', () {
      test(
        'a 64-bogus-id manifest does not outrank a real 2-source one',
        () async {
          final bogus = [for (var i = 0; i < 64; i++) '\$bogus$i'];
          final fetcher = _Fetcher(
            serve: {
              '\$audioAliceA': FetchedAudioEvent(
                senderId: alice,
                content: _audio(deviceId: 'devAlice'),
              ),
              '\$audioBobA': FetchedAudioEvent(
                senderId: bob,
                content: _audio(deviceId: 'devBob'),
              ),
            },
          );
          final states = await _resolve(
            candidates: [
              _peer(
                writer: bob,
                spokenBy: alice,
                eventId: '\$t1',
                sourceAudioEventId: '\$audioAliceA',
                device: 'devAlice',
              ),
            ],
            mergedRecordings: [
              // The bogus manifest has the greater RAW cardinality (64) and an
              // earlier timestamp -- either would win a coverage-blind selection.
              _manifest(
                eventId: '\$mBogus',
                sender: bob,
                sourceEventIds: bogus,
                ts: 500,
              ),
              _manifest(
                eventId: '\$mReal',
                sender: bob,
                sourceEventIds: ['\$audioAliceA', '\$audioBobA'],
                ts: 1000,
              ),
            ],
            fetcher: fetcher,
          );
          // The real manifest is selected on VALIDATED coverage, so the real
          // source is in-manifest and the claim resolves VALID.
          expect(states['\$t1'], ProvenanceState.valid);
        },
      );

      test(
        'validation fetches are bounded, never inflated by claim count',
        () async {
          // 50 claims all referencing the SAME in-manifest source. Memoisation
          // means one fetch, not one per claim.
          final fetcher = _Fetcher(
            serve: {
              '\$audioA': FetchedAudioEvent(
                senderId: alice,
                content: _audio(deviceId: 'devA'),
              ),
              ..._bobServed,
            },
          );
          final claims = [
            for (var i = 0; i < 50; i++)
              _peer(
                writer: bob,
                spokenBy: alice,
                eventId: '\$t$i',
                sourceAudioEventId: '\$audioA',
                device: 'devA',
              ),
          ];
          final states = await _resolve(
            candidates: claims,
            mergedRecordings: [
              _manifest(
                eventId: '\$m1',
                sender: bob,
                sourceEventIds: ['\$audioA', _audioB],
              ),
            ],
            fetcher: fetcher,
          );
          expect(states.values, everyElement(ProvenanceState.valid));
          expect(
            fetcher.calls,
            unorderedEquals(['\$audioA', _audioB]),
            reason:
                'one fetch per listed source, despite 50 claims plus '
                'validation',
          );
        },
      );

      test(
        'a manifest of PART of the call is not the manifest (client#9173)',
        () async {
          // It names alice's recording but not bob's, so it is not a merge of
          // the whole call; a claim against it waits rather than resolving.
          final fetcher = _Fetcher(
            serve: {
              '\$audioA': FetchedAudioEvent(
                senderId: alice,
                content: _audio(deviceId: 'devA'),
              ),
              ..._bobServed,
            },
          );
          final states = await _resolve(
            candidates: [
              _peer(
                writer: bob,
                spokenBy: alice,
                eventId: '\$t1',
                sourceAudioEventId: '\$audioA',
                device: 'devA',
              ),
            ],
            mergedRecordings: [
              _manifest(
                eventId: '\$m1',
                sender: bob,
                sourceEventIds: ['\$audioA'],
              ),
            ],
            fetcher: fetcher,
          );
          expect(states['\$t1'], ProvenanceState.pendingTransient);
        },
      );

      test('a manifest authored by a NON-participant is ignored', () async {
        // Only carol (not on the call) posted a merge. It is not a participant's
        // manifest, so there is no genuine manifest and the claim stays pending.
        final fetcher = _Fetcher(
          serve: {
            '\$audioA': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devA'),
            ),
          },
        );
        final states = await _resolve(
          candidates: [
            _peer(
              writer: bob,
              spokenBy: alice,
              eventId: '\$t1',
              sourceAudioEventId: '\$audioA',
              device: 'devA',
            ),
          ],
          mergedRecordings: [
            _manifest(
              eventId: '\$m1',
              sender: carol,
              sourceEventIds: ['\$audioA'],
            ),
          ],
          fetcher: fetcher,
        );
        expect(states['\$t1'], ProvenanceState.pendingTransient);
      });
    });
  });

  // The manifest selection shared by the reader (above) and the whole-call
  // transcriber's discovery, so the two cannot diverge.
  group('selectCallAudioManifest', () {
    test(
      'breaks a validated-coverage tie by the total order, not list order',
      () async {
        // Two participant-authored manifests, EACH a trusted whole call of two
        // sources (equal coverage). List order puts the LATER-ts one first; the total
        // order must still pick the EARLIER-ts one. Mutation: dropping
        // `_manifestOutranks`'s tie-break (returning only `count > bestCount`)
        // keeps the first-in-list manifest -> RED.
        final fetcher = _Fetcher(
          serve: {
            '\$srcLate': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devLate'),
            ),
            '\$srcLateBob': FetchedAudioEvent(
              senderId: bob,
              content: _audio(deviceId: 'devLateBob'),
            ),
            '\$srcEarlyAlice': FetchedAudioEvent(
              senderId: alice,
              content: _audio(deviceId: 'devEarlyAlice'),
            ),
            '\$srcEarly': FetchedAudioEvent(
              senderId: bob,
              content: _audio(deviceId: 'devEarly'),
            ),
          },
        );
        final selection = await selectCallAudioManifest(
          mergedRecordings: [
            _manifest(
              eventId: '\$mLate',
              sender: bob,
              sourceEventIds: ['\$srcLate', '\$srcLateBob'],
              ts: 2000,
            ),
            _manifest(
              eventId: '\$mEarly',
              sender: bob,
              sourceEventIds: ['\$srcEarlyAlice', '\$srcEarly'],
              ts: 1000,
            ),
          ],
          participants: const {alice, bob},
          callKey: _callKey,
          resolve: audioResolverFor(fetcher.fetch, _room),
        );
        expect(selection.manifest?.eventId, '\$mEarly');
        expect(selection.uncertain, isFalse);
      },
    );

    test('reports uncertain when a validation fetch is transient', () async {
      // The pending source undercounts its manifest, so the selection may be
      // wrong; the flag is what lets both callers refuse to commit to it.
      final fetcher = _Fetcher(
        serve: {
          '\$srcOk': FetchedAudioEvent(
            senderId: alice,
            content: _audio(deviceId: 'devOk'),
          ),
        },
        throwing: {'\$srcPending'},
      );
      final selection = await selectCallAudioManifest(
        mergedRecordings: [
          _manifest(eventId: '\$mOk', sender: bob, sourceEventIds: ['\$srcOk']),
          _manifest(
            eventId: '\$mPending',
            sender: bob,
            sourceEventIds: ['\$srcPending'],
          ),
        ],
        participants: const {alice, bob},
        callKey: _callKey,
        resolve: audioResolverFor(fetcher.fetch, _room),
      );
      expect(selection.uncertain, isTrue);
    });
  });

  group('fetchCallTranscript provenance-failure fallback', () {
    // The production resolver reaches the network (the audio manifest fetch and
    // a per-event fetch), and only its per-event fetches catch their own
    // failure -- the manifest relations fetch can still throw. A throw there
    // must NOT take the whole read down and hide the AUTHENTIC halves too; it
    // falls back to an empty verdict map, so every peer claim is held pending
    // and every authentic half still renders (the documented safe direction).

    // One authentic half from alice and one peer claim (alice writing bob's
    // speech), served on a single exhausted page. The peer claim makes the
    // resolver fire.
    MatrixEvent transcriptEvent(
      String sender, {
      required List<String> texts,
      String? spokenBy,
      String? sourceAudioEventId,
    }) => MatrixEvent(
      type: CallTranscriptContent.relType,
      eventId: '\$ev-$sender-${spokenBy ?? 'own'}',
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      content: {
        'call_key': _callKey,
        'segments': [
          for (final t in texts) {'text': t},
        ],
        'spoken_by': ?spokenBy,
        'source_audio_event_id': ?sourceAudioEventId,
        ...const HalfAccounting(
          chunksCaptured: 1,
          chunksTranscribed: 1,
          declared: true,
        ).toJson(),
      },
    );

    RelationsFetcher onePage(List<MatrixEvent> chunk) =>
        ({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async => (chunk: chunk, nextBatch: null);

    test('a THROWING resolver renders the authentic halves and holds the peer '
        'claim pending, rather than failing the whole read', () async {
      // Mutation proof: removing the try/catch around resolveProvenance lets
      // this throw propagate, so `fetchCallTranscript` throws and the read
      // (with alice's authentic half) is lost -> RED.
      final transcript = await fetchCallTranscript(
        fetch: onePage([
          transcriptEvent(alice, texts: const ['hola alice']),
          transcriptEvent(
            alice,
            texts: const ['words for bob'],
            spokenBy: bob,
            sourceAudioEventId: '\$audioBob',
          ),
        ]),
        roomId: _room,
        callKey: _callKey,
        expectedSenders: const [alice, bob],
        resolveProvenance: (_) async =>
            throw Exception('manifest fetch failed'),
      );

      // The authentic half survived the resolver failure.
      final aliceHalf = transcript.halves.firstWhere(
        (h) => h.senderId == alice,
      );
      expect(aliceHalf.state, HalfState.present);
      expect(aliceHalf.segments.map((s) => s.text), contains('hola alice'));

      // The peer claim was held pending -- never collapsed to its writer and
      // never attributed to bob, so its words render nowhere.
      expect(
        transcript.halves.firstWhere((h) => h.senderId == bob).state,
        isNot(HalfState.present),
      );
      expect(
        transcript.halves.expand((h) => h.segments).map((s) => s.text),
        isNot(contains('words for bob')),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_provenance.dart';

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
);

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
          _manifest(eventId: '\$m1', sender: bob, sourceEventIds: ['\$audioA']),
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
          _manifest(eventId: '\$m1', sender: bob, sourceEventIds: ['\$audioA']),
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
              sourceEventIds: ['\$audioReal'],
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

    test(
      'a redacted source is UNAVAILABLE, not pending and not the writer',
      () async {
        final fetcher = _Fetcher(
          serve: {
            '\$audioReal': FetchedAudioEvent(
              senderId: alice,
              content: _audio(),
            ),
            '\$audioGone': FetchedAudioEvent(senderId: alice, redacted: true),
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
              sourceEventIds: ['\$audioReal', '\$audioGone'],
            ),
          ],
          fetcher: fetcher,
        );
        expect(states['\$t1'], ProvenanceState.unavailableTerminal);
      },
    );

    test('a not-found source (in the manifest) is UNAVAILABLE', () async {
      final fetcher = _Fetcher(
        serve: {
          '\$audioReal': FetchedAudioEvent(senderId: alice, content: _audio()),
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
            sourceEventIds: ['\$audioReal', '\$audioGone'],
          ),
        ],
        fetcher: fetcher,
      );
      expect(states['\$t1'], ProvenanceState.unavailableTerminal);
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
                sourceEventIds: ['\$audioA'],
              ),
            ],
            fetcher: fetcher,
          );
          expect(states.values, everyElement(ProvenanceState.valid));
          expect(
            fetcher.calls,
            ['\$audioA'],
            reason:
                'one fetch for the source, despite 50 claims plus validation',
          );
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
}

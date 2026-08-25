// A real homeserver, the real writer, the real reader.
//
// Everything else in this feature's suite runs against fakes, which is right
// for the rules but cannot answer the question this file exists for: does a
// half we actually WRITE come back through a real relations query, and does
// what comes back assemble into what the reader expects?
//
// The step-0 probe answered a narrower version of that by hand with curl. This
// runs the production code paths end to end, so a change to either side that
// breaks the contract between them fails here rather than on staging.
//
// Skipped unless a homeserver is pointed at, so it never runs in CI or on a
// laptop without the local stack:
//   PANGEA_E2E_HS=http://localhost:8008 \
//   dart test test/pangea/calls/e2e/transcript_roundtrip_e2e.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';
import 'e2e_matrix.dart';

void main() {
  final homeserver = Platform.environment['PANGEA_E2E_HS'] ?? '';

  // Skipped through the runner rather than by returning early, so the reason is
  // printed. A run that quietly does nothing reads as a pass.
  final skip = homeserver.isEmpty
      ? 'set PANGEA_E2E_HS to a homeserver to run the transcript round-trip '
            'against it'
      : null;

  group('call transcript round-trip', () {
    late E2eMatrix alice;
    late E2eMatrix bob;
    late String roomId;
    late String callKey;

    setUpAll(() async {
      alice = await E2eMatrix.login(homeserver, 'learner', 'learnerpass');
      bob = await E2eMatrix.login(homeserver, 'calltester', 'calltesterpass');

      roomId = await alice.createRoom('transcript round-trip');
      await alice.invite(roomId, bob.userId);
      await bob.join(roomId);

      // The anchor both sides know: a membership STATE event, exactly as a real
      // call's call_key is.
      callKey = await alice.firstMemberEventId(roomId);
    });

    tearDownAll(() async {
      await alice.leave(roomId);
      await bob.leave(roomId);
    });

    test(
      'both halves survive a real write and a real relations read',
      () async {
        await writeCallTranscript(
          send: alice.sender(roomId, CallTranscriptContent.relType),
          callKey: callKey,
          senderId: alice.userId,
          segments: const [
            TranscriptSegment('hola que tal'),
            TranscriptSegment('me llamo alice'),
          ],
          chunksCaptured: 2,
          chunksTranscribed: 2,
          chunksLost: 0,
          drainComplete: true,
          langCode: 'es',
        );

        await writeCallTranscript(
          send: bob.sender(roomId, CallTranscriptContent.relType),
          callKey: callKey,
          senderId: bob.userId,
          segments: const [TranscriptSegment('muy bien gracias')],
          chunksCaptured: 1,
          chunksTranscribed: 1,
          chunksLost: 0,
          drainComplete: true,
          langCode: 'es',
        );

        final transcript = await fetchCallTranscript(
          fetch: alice.relationsFetcher(),
          roomId: roomId,
          callKey: callKey,
          expectedSenders: [alice.userId, bob.userId],
        );

        expect(transcript.halves, hasLength(2));

        final mine = transcript.halves.firstWhere(
          (h) => h.senderId == alice.userId,
        );
        final theirs = transcript.halves.firstWhere(
          (h) => h.senderId == bob.userId,
        );

        expect(mine.segments.map((s) => s.text), [
          'hola que tal',
          'me llamo alice',
        ]);
        expect(theirs.segments.map((s) => s.text), ['muy bien gracias']);

        // The whole point of the accounting: a complete half must read complete
        // after a real round trip, or the view will hedge on every transcript.
        expect(mine.state, HalfState.present);
        expect(theirs.state, HalfState.present);
      },
    );

    test('a speaker who never wrote is ABSENT, not merely missing', () async {
      // The distinction the design rests on, proven against a real exhausted
      // read rather than a fake that was told to say so.
      final key = await alice.sendMarker(roomId);

      await writeCallTranscript(
        send: alice.sender(roomId, CallTranscriptContent.relType),
        callKey: key,
        senderId: alice.userId,
        segments: const [TranscriptSegment('solo yo')],
        chunksCaptured: 1,
        chunksTranscribed: 1,
        chunksLost: 0,
        drainComplete: true,
      );

      final transcript = await fetchCallTranscript(
        fetch: alice.relationsFetcher(),
        roomId: roomId,
        callKey: key,
        expectedSenders: [alice.userId, bob.userId],
      );

      expect(
        transcript.halves.firstWhere((h) => h.senderId == bob.userId).state,
        HalfState.absent,
      );
      expect(transcript.readerStoppedEarly, isFalse);
    });

    test('an abandoned drain still reads as incomplete off the wire', () async {
      final key = await alice.sendMarker(roomId);

      await writeCallTranscript(
        send: alice.sender(roomId, CallTranscriptContent.relType),
        callKey: key,
        senderId: alice.userId,
        segments: const [TranscriptSegment('lo que alcance a decir')],
        chunksCaptured: 4,
        chunksTranscribed: 2,
        // The abandoned drain is the gap here, not a lost chunk.
        chunksLost: 0,
        drainComplete: false,
      );

      final transcript = await fetchCallTranscript(
        fetch: alice.relationsFetcher(),
        roomId: roomId,
        callKey: key,
        expectedSenders: [alice.userId],
      );

      final half = transcript.halves.single;
      expect(half.state, HalfState.incomplete);
      expect(half.accounting.drainComplete, isFalse);
      expect(half.accounting.chunksTranscribed, 2);
      expect(half.accounting.chunksCaptured, 4);
    });

    test('a half the server accepted is under the size limit', () async {
      // The packing exists so the server does not reject the event. Only a real
      // homeserver can confirm the limit it actually enforces.
      final key = await alice.sendMarker(roomId);

      final wrote = await writeCallTranscript(
        send: alice.sender(roomId, CallTranscriptContent.relType),
        callKey: key,
        senderId: alice.userId,
        segments: [
          for (var i = 0; i < 4000; i++)
            TranscriptSegment('una frase larga de relleno numero $i'),
        ],
        chunksCaptured: 40,
        chunksTranscribed: 40,
        chunksLost: 0,
        drainComplete: true,
      );
      expect(wrote, isTrue, reason: 'the server accepted the packed half');

      final transcript = await fetchCallTranscript(
        fetch: alice.relationsFetcher(),
        roomId: roomId,
        callKey: key,
        expectedSenders: [alice.userId],
      );

      final half = transcript.halves.single;
      expect(half.segments, isNotEmpty);
      expect(half.accounting.truncated, isTrue);
      expect(half.state, HalfState.incomplete);
    });
  }, skip: skip);
}

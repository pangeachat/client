import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_half_in_flight.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/call_upload_gate.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'call_transcript_sink_test.dart' show chunk, spokenWord;

/// client#9302: the credit no longer waits behind the publishes, and every
/// step after hangup is bounded.
void main() {
  setUp(CallUploadGate.resetShared);
  setUp(CallHalfInFlight.resetForTest);

  late List<String> order;
  late List<List<String>> transcriptAttempts;
  late List<({String? callKey, Map<String, dynamic>? live, String? txn})>
  prepared;

  setUp(() {
    order = [];
    transcriptAttempts = [];
    prepared = [];
  });

  Future<CallTranscriptSink> sink() async {
    final s = CallTranscriptSink(
      userL1: 'en',
      userL2: 'es',
      transcribe: (_) async => spokenWord('hola'),
    );
    await s.deliver(chunk(0));
    return s;
  }

  CallRecord record(
    CallTranscriptSink transcripts, {
    Future<void> Function()? analytics,
    Future<void> Function()? audio,
    Future<void> Function()? transcript,
    FutureOr<List<TranscriptSegment>> Function()? recording,
    bool withTxnIds = false,
    bool withPrepare = false,
    Duration creditDeadline = const Duration(seconds: 15),
    Duration recordingDeadline = const Duration(seconds: 120),
    Duration transcriptAttemptDeadline = const Duration(seconds: 60),
  }) => CallRecord(
    roomId: '!r:server',
    transcripts: transcripts,
    sendEvent: (content, txid) async => '\$card',
    analytics: (id, uses, lang) async {
      order.add('credit');
      await analytics?.call();
    },
    recordingSegments: recording,
    publishTranscript:
        ({
          required String callKey,
          required List<TranscriptSegment> segments,
          required int chunksCaptured,
          required int chunksTranscribed,
          required int chunksLost,
          required int chunksRefusedUnsubscribed,
          required int chunksSuppressed,
          required bool captureRefused,
          required bool drainComplete,
          String? langCode,
        }) async {
          order.add('transcript');
          transcriptAttempts.add(segments.map((s) => s.text).toList());
          await transcript?.call();
        },
    publishCallAudio: ({required String? callKey}) async {
      order.add('audio');
      await audio?.call();
    },
    prepareCallAudio: !withPrepare
        ? null
        : ({
            required String? callKey,
            Map<String, dynamic>? liveTranscriptContent,
            String? transcriptTxnId,
          }) async {
            order.add('prepare');
            prepared.add((
              callKey: callKey,
              live: liveTranscriptContent,
              txn: transcriptTxnId,
            ));
          },
    buildLiveTranscript: !withPrepare
        ? null
        : ({
            required String callKey,
            required List<TranscriptSegment> segments,
            required int chunksCaptured,
            required int chunksTranscribed,
            required int chunksLost,
            required int chunksRefusedUnsubscribed,
            required int chunksSuppressed,
            required bool captureRefused,
            required bool drainComplete,
            String? langCode,
          }) async => (
            content: {'segments': segments.map((s) => s.text).toList()},
            txnId: 'transcript-txn',
          ),
    audioTxnIdFor: withTxnIds ? (k) => 'audio:$k' : null,
    transcriptTxnIdFor: withTxnIds ? (k) => 'transcript:$k' : null,
    creditDeadline: creditDeadline,
    recordingTranscriptDeadline: recordingDeadline,
    transcriptAttemptDeadline: transcriptAttemptDeadline,
  );

  test('the learner is credited BEFORE either half publishes', () async {
    final r = record(
      await sink(),
      recording: () => [TranscriptSegment('from the recording', atMs: 1)],
    );
    await r.finish(
      duration: const Duration(seconds: 30),
      video: false,
      callKey: '\$k',
    );
    expect(order.first, 'credit');
    expect(order, containsAll(['audio', 'transcript']));
  });

  test(
    'a stuck upload cannot hold the credit (the #9302 kill window)',
    () async {
      final upload = Completer<void>();
      final r = record(
        await sink(),
        audio: () => upload.future,
        recording: () => const <TranscriptSegment>[],
      );
      unawaited(
        r.finish(
          duration: const Duration(seconds: 30),
          video: false,
          callKey: '\$k',
        ),
      );
      await pumpEventQueue();
      expect(order, contains('credit'));
      expect(
        order,
        contains('transcript'),
        reason: 'the transcript half does not wait for the audio upload',
      );
      upload.complete();
    },
  );

  test(
    'publishing waits at most the credit deadline; the credit is not canceled',
    () async {
      final credit = Completer<void>();
      final r = record(
        await sink(),
        analytics: () => credit.future,
        creditDeadline: const Duration(milliseconds: 20),
      );
      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: '\$k',
      );
      expect(order, containsAll(['credit', 'transcript', 'audio']));
      credit.complete();
      await pumpEventQueue();
    },
  );

  test(
    'the live half stands when the recording is not transcribed in time',
    () async {
      final never = Completer<List<TranscriptSegment>>();
      final r = record(
        await sink(),
        recording: () => never.future,
        recordingDeadline: const Duration(milliseconds: 20),
      );
      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: '\$k',
      );
      expect(transcriptAttempts, hasLength(1));
      expect(transcriptAttempts.single, ['hola']);
    },
  );

  test('a hung transcript send parks instead of hanging the finish', () async {
    final r = record(
      await sink(),
      transcript: () => Completer<void>().future,
      recording: () => const <TranscriptSegment>[],
      transcriptAttemptDeadline: const Duration(milliseconds: 20),
    );
    await r
        .finish(
          duration: const Duration(seconds: 30),
          video: false,
          callKey: '\$k',
        )
        .timeout(const Duration(seconds: 5));
    expect(
      transcriptAttempts,
      hasLength(1),
      reason: 'a park is not a failure to retry: the outbox owns it now',
    );
  });

  test(
    'the recording is finalised locally before the credit, with the live half '
    'frozen beside it',
    () async {
      final r = record(
        await sink(),
        withPrepare: true,
        recording: () => const <TranscriptSegment>[],
      );
      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: '\$k',
      );
      expect(order.take(2), ['prepare', 'credit']);
      expect(prepared.single.callKey, '\$k');
      expect(prepared.single.txn, 'transcript-txn');
      expect(prepared.single.live?['segments'], ['hola']);
    },
  );

  test(
    'both halves are claimed while the finish works, then released',
    () async {
      final upload = Completer<void>();
      final r = record(
        await sink(),
        withTxnIds: true,
        audio: () => upload.future,
        recording: () => const <TranscriptSegment>[],
      );
      final finishing = r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: '\$k',
      );
      await pumpEventQueue();
      expect(CallHalfInFlight.isClaimed('audio:\$k'), isTrue);
      expect(
        CallHalfInFlight.isClaimed('transcript:\$k'),
        isFalse,
        reason: 'a half releases its own claim the moment it settles',
      );
      upload.complete();
      await finishing;
      expect(CallHalfInFlight.isClaimed('audio:\$k'), isFalse);
    },
  );

  test('the transcript half is claimed while it publishes', () async {
    final publishing = Completer<void>();
    final r = record(
      await sink(),
      withTxnIds: true,
      transcript: () => publishing.future,
      recording: () => const <TranscriptSegment>[],
    );
    final finishing = r.finish(
      duration: const Duration(seconds: 30),
      video: false,
      callKey: '\$k',
    );
    await pumpEventQueue();
    expect(order, contains('transcript'));
    expect(CallHalfInFlight.isClaimed('transcript:\$k'), isTrue);
    publishing.complete();
    await finishing;
    expect(CallHalfInFlight.isClaimed('transcript:\$k'), isFalse);
  });

  test('a half someone else is working on is left to them', () async {
    final other = CallHalfInFlight.claim('audio:\$k');
    final r = record(
      await sink(),
      withTxnIds: true,
      recording: () => const <TranscriptSegment>[],
    );
    await r.finish(
      duration: const Duration(seconds: 30),
      video: false,
      callKey: '\$k',
    );
    expect(order, isNot(contains('audio')));
    expect(order, contains('transcript'));
    expect(
      CallHalfInFlight.isClaimed('audio:\$k'),
      isTrue,
      reason: 'the finish must not release a claim it never held',
    );
    CallHalfInFlight.release(other);
  });
}

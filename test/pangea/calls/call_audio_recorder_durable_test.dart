import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Logs, MatrixEvent;

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart';
import 'package:fluffychat/routes/chat/calls/call_half_resume.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_outbox.dart';
import 'call_transcript_sink_test.dart' show spokenWord;

const _callKey = '\$membership:example.com';

/// A recording survives an app kill, and every network step after hangup is
/// bounded (client#9302).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryCallAudioPendingStore store;
  late List<Map<String, dynamic>> sent;
  late int uploads;
  late int transcribes;
  Completer<Uri>? uploadGate;

  setUp(() {
    store = InMemoryCallAudioPendingStore();
    sent = [];
    uploads = 0;
    transcribes = 0;
    uploadGate = null;
  });

  CallAudioRecorder recorder({
    Duration Function(int)? attemptBound,
    Duration sessionBudget = const Duration(minutes: 10),
    Duration sttBudget = const Duration(seconds: 120),
    bool withStt = false,
    CallAudioPendingStore? pending,
  }) => CallAudioRecorder(
    senderId: '@alice:example.com',
    deviceId: 'DEVICEA',
    elapsedMs: () => 0,
    retryDelay: Duration.zero,
    reanchorInterval: Duration.zero,
    pendingStore: pending ?? store,
    roomId: '!r:example.com',
    uploadSessionBudget: sessionBudget,
    uploadAttemptBound: attemptBound ?? callAudioUploadAttemptBoundForTest,
    recordingTranscriptBudget: sttBudget,
    transcribe: withStt
        ? (_) async {
            transcribes++;
            return spokenWord('hola');
          }
        : null,
    userL1: withStt ? 'en' : null,
    userL2: withStt ? 'es' : null,
    upload: (bytes, {required filename, required contentType}) {
      uploads++;
      final gate = uploadGate;
      if (gate != null) return gate.future;
      return Future.value(Uri.parse('mxc://example.com/blob'));
    },
    send: (content, txnId) async {
      sent.add(content);
      return '\$event:example.com';
    },
  );

  /// The durable write hashes off the UI thread, so it settles in real time.
  Future<List<PendingCallAudio>> held() async {
    for (var i = 0; i < 200; i++) {
      final items = await store.recover();
      if (items.isNotEmpty) return items;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return store.recover();
  }

  void record(CallAudioRecorder r) {
    r.onRunStarted(1000, 16000, 1);
    r.onFrame(Int16List.fromList(List.filled(1600, 1000)));
    r.onRunEnded();
  }

  test('prepare keeps the recording durably before any network step', () async {
    final r = recorder();
    record(r);
    await r.prepare(
      wasCarrier: true,
      callKey: _callKey,
      liveTranscriptContent: {'live': true},
      transcriptTxnId: 'transcript-txn',
    );
    final items = await held();

    expect(uploads, 0, reason: 'prepare never touches the network');
    expect(items, hasLength(1));
    expect(items.single.status, PendingCallAudio.persisted);
    expect(items.single.liveTranscriptContent, {'live': true});
    expect(items.single.transcriptTxnId, 'transcript-txn');
    expect(await store.readVerified(items.single), isNotNull);
  });

  test('a moved call\'s links survive the durable copy and the resume that '
      'sends it after a kill (client#9173)', () async {
    final r = recorder();
    r.halfLinks = (continuedFrom: 'PHONE', handedOverTo: 'TABLET');
    record(r);
    await r.prepare(wasCarrier: true, callKey: _callKey);
    final item = (await held()).single;

    // The process dies here; the next launch resumes from the durable copy.
    final resent = <Map<String, dynamic>>[];
    await CallHalfResumer(
      store: store,
      outbox: CallTranscriptOutbox(store: InMemoryPendingCallTranscriptStore()),
      fetch:
          ({
            required String roomId,
            required String eventId,
            required String relType,
            String? from,
          }) async => (chunk: <MatrixEvent>[], nextBatch: null),
      upload: (b, {required filename, required contentType}) async =>
          Uri.parse('mxc://example.com/blob'),
      send: (roomId, type, content, txn) async {
        if (type == CallAudioContent.relType) resent.add(content);
        return '\$sent';
      },
      onAudioPosted: (roomId, callKey, owner, device) {},
    ).resume(owner: item.owner);

    final content = CallAudioContent.fromJson(resent.single)!;
    expect(content.continuedFrom, 'PHONE');
    expect(content.handedOverTo, 'TABLET');
  });

  test('a confirmed send removes the durable copy', () async {
    final r = recorder();
    record(r);
    await r.prepare(wasCarrier: true, callKey: _callKey);
    expect(await held(), hasLength(1));
    await r.finish(wasCarrier: true, callKey: _callKey);
    expect(sent, hasLength(1));
    expect(await store.recover(), isEmpty);
  });

  test(
    'a hung upload parks at its attempt bound and the recording stays for the '
    'next launch',
    () async {
      uploadGate = Completer<Uri>();
      final r = recorder(attemptBound: (_) => const Duration(milliseconds: 20));
      record(r);
      await r.prepare(wasCarrier: true, callKey: _callKey);
      expect(await held(), hasLength(1));

      final logsBefore = Logs().outputEvents.length;
      await r
          .finish(wasCarrier: true, callKey: _callKey)
          .timeout(const Duration(seconds: 5));
      expect(uploads, 1, reason: 'a park is not retried in this session');
      expect(sent, isEmpty);
      expect((await store.recover()).single.status, PendingCallAudio.persisted);

      // The abandoned upload lands later: logged as an orphan, nothing written.
      uploadGate!.complete(Uri.parse('mxc://example.com/late'));
      await pumpEventQueue();
      expect(
        Logs().outputEvents
            .skip(logsBefore)
            .any((e) => e.title.contains('mxc://example.com/late')),
        isTrue,
      );
      expect((await store.recover()).single.mxcUrl, isNull);
    },
  );

  test('the upload starts only once the recording is on disk', () async {
    final gate = Completer<void>();
    final gated = _GatedPersistStore(gate.future);
    final r = recorder(pending: gated);
    record(r);
    final finishing = r.finish(wasCarrier: true, callKey: _callKey);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(uploads, 0, reason: 'a kill during the upload must find it on disk');
    gate.complete();
    await finishing;
    expect(uploads, 1);
    expect(sent, hasLength(1));
  });

  test('a spent upload budget parks without starting an upload', () async {
    final r = recorder(sessionBudget: Duration.zero);
    record(r);
    await r.finish(wasCarrier: true, callKey: _callKey);
    expect(uploads, 0);
    expect(sent, isEmpty);
  });

  test(
    'segments are ready (empty) for a device that was not carrying',
    () async {
      final r = recorder();
      record(r);
      await r.finish(wasCarrier: false, callKey: _callKey);
      expect(await r.recordingSegmentsReady, isEmpty);
    },
  );

  test(
    'an over-budget transcription sends no piece and yields no half',
    () async {
      final r = recorder(withStt: true, sttBudget: Duration.zero);
      record(r);
      await r.finish(wasCarrier: true, callKey: _callKey);
      expect(transcribes, 0);
      expect(await r.recordingSegmentsReady, isEmpty);
      expect(sent, hasLength(1), reason: 'the audio half is unaffected');
    },
  );

  test('within budget the recording-based segments are delivered', () async {
    final r = recorder(withStt: true);
    record(r);
    await r.prepare(wasCarrier: true, callKey: _callKey);
    final segments = await r.recordingSegmentsReady;
    expect(segments.map((s) => s.text), ['hola']);
    expect(uploads, 0, reason: 'the transcript never waits on the upload');
  });
}

class _GatedPersistStore extends InMemoryCallAudioPendingStore {
  final Future<void> gate;
  _GatedPersistStore(this.gate);

  @override
  Future<bool> persist(PendingCallAudio item, Uint8List wav) async {
    await gate;
    return super.persist(item, wav);
  }
}

Duration callAudioUploadAttemptBoundForTest(int bytes) =>
    const Duration(seconds: 5);

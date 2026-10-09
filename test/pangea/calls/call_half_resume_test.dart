import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';
import 'package:fluffychat/routes/chat/calls/call_half_in_flight.dart';
import 'package:fluffychat/routes/chat/calls/call_half_resume.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_outbox.dart';

const _owner = '@a:s';
const _device = 'DEV';
const _room = '!r:s';
const _key = '\$k';

MatrixEvent _half(String type, {String sender = _owner, String? device}) =>
    MatrixEvent(
      type: type,
      content: {'call_key': _key, 'device_id': device ?? _device},
      senderId: sender,
      eventId: '\$e${type.hashCode}',
      originServerTs: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(CallHalfInFlight.resetForTest);

  late InMemoryCallAudioPendingStore store;
  late InMemoryPendingCallTranscriptStore outboxStore;
  late List<MatrixEvent> roomHalves;
  late bool roomReadFails;
  late String? failRelType;
  late List<({String type, Map<String, dynamic> content, String txn})> sends;
  late int uploads;
  late List<String> posted;

  final audioTxn = CallAudioContent.txnId(_key, _owner, _device);
  final transcriptTxn = CallTranscriptContent.txnId(_key, _owner, _device);
  final bytes = Uint8List.fromList(List.generate(400, (i) => i % 7));

  setUp(() {
    store = InMemoryCallAudioPendingStore();
    outboxStore = InMemoryPendingCallTranscriptStore();
    roomHalves = [];
    roomReadFails = false;
    failRelType = null;
    sends = [];
    uploads = 0;
    posted = [];
  });

  CallHalfResumer resumer() => CallHalfResumer(
    store: store,
    outbox: CallTranscriptOutbox(store: outboxStore),
    fetch:
        ({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async {
          if (roomReadFails || relType == failRelType) {
            throw Exception('offline');
          }
          return (
            chunk: roomHalves.where((e) => e.type == relType).toList(),
            nextBatch: null,
          );
        },
    upload: (b, {required filename, required contentType}) async {
      uploads++;
      return Uri.parse('mxc://s/blob');
    },
    send: (roomId, type, content, txn) async {
      sends.add((type: type, content: content, txn: txn));
      return '\$sent';
    },
    onAudioPosted: (roomId, callKey, owner, device) => posted.add(callKey),
  );

  Future<PendingCallAudio> seed({
    String status = PendingCallAudio.persisted,
  }) async {
    final item = PendingCallAudio.create(
      audioTxnId: audioTxn,
      transcriptTxnId: transcriptTxn,
      roomId: _room,
      owner: _owner,
      deviceId: _device,
      generationId: 'g',
      callKey: _key,
      expectedBytes: bytes.length,
      contentSha256: 'unused-in-memory',
      audioContent: {'call_key': _key, 'url': ''},
      liveTranscriptContent: {'call_key': _key, 'live': true},
    );
    await store.persist(item, bytes);
    if (status != PendingCallAudio.persisted) {
      await store.update(item.withStatus(status, mxcUrl: 'mxc://s/earlier'));
    }
    return item;
  }

  test('a killed call: the live transcript half and the recording both land, '
      'under their original transaction ids', () async {
    await seed();
    await resumer().resume(owner: _owner);

    expect(sends.map((s) => s.txn), [transcriptTxn, audioTxn]);
    expect(sends.first.content['live'], isTrue);
    expect(sends.last.content['url'], 'mxc://s/blob');
    expect(uploads, 1);
    expect(await store.recover(), isEmpty);
    expect(posted, [_key]);
    expect(
      await outboxStore.readAll(),
      isEmpty,
      reason: 'the confirmed transcript is not left for a replay',
    );
  });

  test('a half that landed late is closed without being sent again', () async {
    await seed();
    roomHalves = [
      _half(CallAudioContent.relType),
      _half(CallTranscriptContent.relType),
    ];
    await resumer().resume(owner: _owner);
    expect(sends, isEmpty);
    expect(uploads, 0);
    expect(await store.recover(), isEmpty);
  });

  test(
    'another device\'s half for the same call is not mistaken for ours',
    () async {
      await seed();
      roomHalves = [
        _half(CallAudioContent.relType, device: 'OTHER'),
        _half(CallTranscriptContent.relType, sender: '@b:s'),
      ];
      await resumer().resume(owner: _owner);
      expect(sends.map((s) => s.txn), [transcriptTxn, audioTxn]);
    },
  );

  test('a room that cannot be read sends nothing and keeps the item', () async {
    await seed();
    roomReadFails = true;
    await resumer().resume(owner: _owner);
    expect(sends, isEmpty);
    expect(uploads, 0);
    expect(await store.recover(), hasLength(1));
  });

  test(
    'an audio read that fails is never taken as absent: nothing uploaded',
    () async {
      await seed();
      roomHalves = [_half(CallTranscriptContent.relType)];
      failRelType = CallAudioContent.relType;
      await resumer().resume(owner: _owner);
      expect(uploads, 0);
      expect(sends, isEmpty);
      expect(await store.recover(), hasLength(1));
    },
  );

  test(
    'an already-uploaded item is sent with its url, not re-uploaded',
    () async {
      await seed(status: PendingCallAudio.uploaded);
      roomHalves = [_half(CallTranscriptContent.relType)];
      await resumer().resume(owner: _owner);
      expect(uploads, 0);
      expect(sends.single.content['url'], 'mxc://s/earlier');
    },
  );

  test(
    'a transcript half already in the outbox is left to the outbox',
    () async {
      await seed();
      await outboxStore.write(transcriptTxn, {
        'room_id': _room,
        'txn_id': transcriptTxn,
        'owner': _owner,
        'content': {'recording': true},
      });
      await resumer().resume(owner: _owner);
      expect(sends.map((s) => s.txn), [audioTxn]);
    },
  );

  test('a half claimed by the live finish is skipped this pass', () async {
    await seed();
    final live = CallHalfInFlight.claim(audioTxn);
    roomHalves = [_half(CallTranscriptContent.relType)];
    await resumer().resume(owner: _owner);
    expect(sends, isEmpty);
    expect(await store.recover(), hasLength(1));
    CallHalfInFlight.release(live);
  });

  test('another account\'s recording is never resumed', () async {
    await seed();
    await resumer().resume(owner: '@b:s');
    expect(sends, isEmpty);
    expect(uploads, 0);
  });

  test('a hung upload parks the item instead of holding the claim', () async {
    await seed();
    roomHalves = [_half(CallTranscriptContent.relType)];
    final r = CallHalfResumer(
      store: store,
      outbox: CallTranscriptOutbox(store: outboxStore),
      fetch:
          ({
            required String roomId,
            required String eventId,
            required String relType,
            String? from,
          }) async => (
            chunk: roomHalves.where((e) => e.type == relType).toList(),
            nextBatch: null,
          ),
      upload: (b, {required filename, required contentType}) =>
          Completer<Uri>().future,
      send: (roomId, type, content, txn) async => '\$sent',
      uploadAttemptBound: (_) => const Duration(milliseconds: 20),
    );
    await r.resume(owner: _owner).timeout(const Duration(seconds: 5));
    expect(CallHalfInFlight.isClaimed(audioTxn), isFalse);
    expect(
      (await store.recover()).single.status,
      PendingCallAudio.persisted,
      reason: 'nothing is written for an abandoned upload',
    );
  });
}

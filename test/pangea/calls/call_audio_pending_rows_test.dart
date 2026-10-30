import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';

/// IndexedDB's two object stores, in memory. What this file proves is the
/// rules; the browser's half of it is route r04.
class _Rows implements PendingCallAudioRows {
  final records = <String, String>{};
  final wavs = <String, Uint8List>{};

  @override
  Future<void> putRecord(String id, String json) async => records[id] = json;
  @override
  Future<String?> getRecord(String id) async => records[id];
  @override
  Future<void> putWav(String id, Uint8List wav) async => wavs[id] = wav;
  @override
  Future<Uint8List?> getWav(String id) async => wavs[id];
  @override
  Future<void> remove(String id) async {
    wavs.remove(id);
    records.remove(id);
  }

  @override
  Future<List<String>> ids() async => records.keys.toList();
}

Future<PendingCallAudio> _item(
  Uint8List wav, {
  String id = 'txn',
  String owner = '@me:server',
  DateTime? now,
}) async => PendingCallAudio.create(
  audioTxnId: id,
  transcriptTxnId: null,
  roomId: '!r:server',
  owner: owner,
  deviceId: 'DEV',
  generationId: 'gen',
  callKey: 'key',
  expectedBytes: wav.length,
  contentSha256: await callAudioSha256(wav),
  audioContent: const {'url': ''},
  now: now,
);

void main() {
  final wav = Uint8List.fromList(List.filled(64, 7));
  late _Rows rows;
  late RowsCallAudioPendingStore store;

  setUp(() {
    rows = _Rows();
    store = RowsCallAudioPendingStore(rows);
    callAudioWaitingToSend.value = false;
  });

  test('a reload finds a persisted recording, whole', () async {
    final item = await _item(wav);
    expect(await store.persist(item, wav), isTrue);
    expect(callAudioWaitingToSend.value, isTrue);

    final reloaded = RowsCallAudioPendingStore(rows);
    final found = await reloaded.recover();
    expect(found.single.status, PendingCallAudio.persisted);
    expect(await reloaded.readVerified(found.single), wav);
  });

  test('a tab killed before its WAV was written leaves nothing', () async {
    final item = await _item(
      wav,
      now: DateTime.now().subtract(const Duration(minutes: 2)),
    );
    await rows.putRecord(
      item.audioTxnId,
      jsonEncode(item.withStatus(PendingCallAudio.persisting).json),
    );
    expect(await store.recover(), isEmpty);
    expect(rows.records, isEmpty);
  });

  test('a WAV written whole under a persisting record is kept', () async {
    final item = await _item(wav);
    await store.persist(item, wav);
    await store.update(item.withStatus(PendingCallAudio.persisting));
    final found = await RowsCallAudioPendingStore(rows).recover();
    expect(found.single.status, PendingCallAudio.persisted);
  });

  test('a WAV that does not match its hash is dropped', () async {
    final item = await _item(wav);
    await store.persist(item, wav);
    rows.wavs[item.audioTxnId] = Uint8List.fromList(List.filled(64, 9));
    expect(await store.recover(), isEmpty);
    expect(rows.wavs, isEmpty);
  });

  test('an item past its retention window is dropped', () async {
    final old = await _item(
      wav,
      now: DateTime.now().subtract(
        PendingCallAudio.ttl + const Duration(minutes: 1),
      ),
    );
    await store.persist(old, wav);
    expect(await store.recover(), isEmpty);
    expect(callAudioWaitingToSend.value, isFalse);
  });

  test('past the cap, the oldest go first', () async {
    for (var i = 0; i <= kMaxPendingCallAudioItems; i++) {
      final item = await _item(
        wav,
        id: 'txn$i',
        now: DateTime.now().subtract(Duration(minutes: i)),
      );
      await store.persist(item, wav);
    }
    final kept = await store.recover();
    expect(kept, hasLength(kMaxPendingCallAudioItems));
    expect(kept.map((i) => i.audioTxnId), isNot(contains('txn5')));
  });

  test('signing out purges that account only', () async {
    await store.persist(await _item(wav, id: 'mine'), wav);
    await store.persist(
      await _item(wav, id: 'theirs', owner: '@them:server'),
      wav,
    );
    await store.purgeOwner('@me:server');
    expect(rows.records.keys, ['theirs']);
  });

  test('an update never brings back a deleted item', () async {
    final item = await _item(wav);
    await store.persist(item, wav);
    await store.delete(item.audioTxnId);
    expect(callAudioWaitingToSend.value, isFalse);
    await store.update(item);
    expect(rows.records, isEmpty);
  });

  test('recovery leaves alone what another tab is still writing', () async {
    final item = await _item(wav);
    final slow = _SlowRows();
    final writing = RowsCallAudioPendingStore(slow);
    final persisted = writing.persist(item, wav);
    await pumpEventQueue();
    expect(await writing.recover(), isEmpty);
    expect(slow.records, isNotEmpty, reason: 'not taken for a dead write');
    slow.release();
    expect(await persisted, isTrue);
    expect((await writing.recover()).single.audioTxnId, item.audioTxnId);
  });
}

/// Holds the WAV write open, as a slow disk would.
class _SlowRows extends _Rows {
  final _released = Completer<void>();

  void release() => _released.complete();

  @override
  Future<void> putWav(String id, Uint8List wav) async {
    await _released.future;
    await super.putWav(id, wav);
  }
}

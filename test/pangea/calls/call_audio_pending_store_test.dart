import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';

/// The crash table: whatever a kill leaves on disk is judged by the sidecar's
/// promised length and hash, never by a file's name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late FileCallAudioPendingStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pending_call_audio_');
    store = FileCallAudioPendingStore(root: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Uint8List wav([int n = 4000, int seed = 1]) =>
      Uint8List.fromList(List.generate(n, (i) => (i * seed) % 251));

  Future<PendingCallAudio> item(
    Uint8List bytes, {
    String txn = 'pangea.call_audio:\$k:@a:s:DEV',
    String owner = '@a:s',
    DateTime? now,
  }) async => PendingCallAudio.create(
    audioTxnId: txn,
    transcriptTxnId: 'pangea.call_transcript:\$k:@a:s:DEV',
    roomId: '!r:s',
    owner: owner,
    deviceId: 'DEV',
    generationId: 'g1',
    callKey: '\$k',
    expectedBytes: bytes.length,
    contentSha256: await callAudioSha256(bytes),
    audioContent: {'call_key': '\$k', 'url': ''},
    liveTranscriptContent: {'segments': []},
    now: now,
  );

  String h(PendingCallAudio i) =>
      FileCallAudioPendingStore.nameFor(i.audioTxnId);
  File f(String name) => File('${dir.path}/$name');

  Future<void> writeSidecar(PendingCallAudio i) =>
      f('${h(i)}.json').writeAsString(jsonEncode(i.json));

  test('a persisted item is recovered and its WAV verifies', () async {
    final bytes = wav();
    final i = await item(bytes);
    expect(await store.persist(i, bytes), isTrue);

    final recovered = await store.recover();
    expect(recovered, hasLength(1));
    expect(recovered.single.status, PendingCallAudio.persisted);
    expect(await store.readVerified(recovered.single), bytes);
  });

  test(
    'killed after the WAV was fsynced but before its rename: promoted',
    () async {
      final bytes = wav();
      final i = await item(bytes);
      await writeSidecar(i); // status persisting
      await f('${h(i)}.wav.tmp').writeAsBytes(bytes);

      final recovered = await store.recover();
      expect(recovered.single.status, PendingCallAudio.persisted);
      expect(await f('${h(i)}.wav').exists(), isTrue);
      expect(await f('${h(i)}.wav.tmp').exists(), isFalse);
    },
  );

  test(
    'killed mid-WAV-write: the partial file is dropped, not uploaded',
    () async {
      final bytes = wav();
      final i = await item(bytes);
      await writeSidecar(i);
      await f('${h(i)}.wav.tmp').writeAsBytes(bytes.sublist(0, 100));

      expect(await store.recover(), isEmpty);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'a right-length but wrong-content file is not trusted (hash, not size)',
    () async {
      final bytes = wav();
      final i = await item(bytes);
      await writeSidecar(i);
      await f('${h(i)}.wav').writeAsBytes(wav(bytes.length, 7));

      expect(await store.recover(), isEmpty);
    },
  );

  test(
    'a damaged WAV beside a complete temp copy resumes from the copy',
    () async {
      final bytes = wav();
      final i = await item(bytes);
      await writeSidecar(i.withStatus(PendingCallAudio.persisted));
      await f('${h(i)}.wav').writeAsBytes(bytes.sublist(0, 10));
      await f('${h(i)}.wav.tmp').writeAsBytes(bytes);

      final recovered = await store.recover();
      expect(recovered, hasLength(1));
      expect(await store.readVerified(recovered.single), bytes);
    },
  );

  test('a WAV with no sidecar, and a stray sidecar tmp, are removed', () async {
    await f('abc.wav').writeAsBytes(wav());
    await f('def.json.tmp').writeAsString('{');
    expect(await store.recover(), isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test('a file changed after persisting fails readVerified', () async {
    final bytes = wav();
    final i = await item(bytes);
    await store.persist(i, bytes);
    await f('${h(i)}.wav').writeAsBytes(wav(bytes.length, 9));
    expect(await store.readVerified(i), isNull);
  });

  test('an item past its retention window is dropped', () async {
    final bytes = wav();
    final i = await item(
      bytes,
      now: DateTime.now().subtract(const Duration(days: 8)),
    );
    await store.persist(i, bytes);
    expect(await store.recover(), isEmpty);
  });

  test('at most five items are kept, newest first', () async {
    for (var n = 0; n < 7; n++) {
      final bytes = wav(100, n + 1);
      await store.persist(
        await item(
          bytes,
          txn: 'txn-$n',
          now: DateTime.now().subtract(Duration(minutes: 10 - n)),
        ),
        bytes,
      );
    }
    final kept = await store.recover();
    expect(kept.map((i) => i.audioTxnId), [
      'txn-6',
      'txn-5',
      'txn-4',
      'txn-3',
      'txn-2',
    ]);
  });

  test('a sent item whose deletes did not finish is cleaned up', () async {
    final bytes = wav();
    final i = await item(bytes);
    await store.persist(i, bytes);
    await store.update(i.withStatus(PendingCallAudio.sent));
    expect(await store.recover(), isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test('sign-out purges only that account\'s recordings', () async {
    final a = wav(100, 1);
    final b = wav(100, 2);
    await store.persist(await item(a, txn: 'a', owner: '@a:s'), a);
    await store.persist(await item(b, txn: 'b', owner: '@b:s'), b);
    await store.purgeOwner('@a:s');
    expect((await store.recover()).map((i) => i.owner), ['@b:s']);
  });

  test('an update never resurrects a deleted item', () async {
    final bytes = wav();
    final i = await item(bytes);
    await store.persist(i, bytes);
    await store.delete(i.audioTxnId);
    await store.update(i.withStatus(PendingCallAudio.uploaded));
    expect(dir.listSync(), isEmpty);
  });
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';

@JS('indexedDB')
external _IdbFactory get _indexedDb;

extension type _IdbFactory._(JSObject _) implements JSObject {
  external _IdbRequest open(String name, int version);
}

extension type _IdbRequest._(JSObject _) implements JSObject {
  external JSAny? get result;
  external JSAny? get error;
  external set onsuccess(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external set onupgradeneeded(JSFunction? handler);
}

extension type _IdbDatabase._(JSObject _) implements JSObject {
  external JSAny createObjectStore(String name);
  external _IdbTransaction transaction(JSArray<JSString> stores, String mode);
}

extension type _IdbTransaction._(JSObject _) implements JSObject {
  external _IdbObjectStore objectStore(String name);
  external JSAny? get error;
  external set oncomplete(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external set onabort(JSFunction? handler);
}

extension type _IdbObjectStore._(JSObject _) implements JSObject {
  external _IdbRequest put(JSAny? value, JSAny? key);
  external _IdbRequest get(JSAny? key);
  external _IdbRequest delete(JSAny? key);
  external _IdbRequest getAllKeys();
}

const _dbName = 'pangea_call_audio_pending';
const _records = 'records';
const _wavs = 'wavs';

/// Pending call recordings in this browser's IndexedDB, so a tab that dies
/// before its recording is sent still has it on the next load.
class _IndexedDbRows implements PendingCallAudioRows {
  Future<_IdbDatabase>? _opened;

  Future<_IdbDatabase> _db() => _opened ??= _open();

  Future<_IdbDatabase> _open() {
    final done = Completer<_IdbDatabase>();
    final request = _indexedDb.open(_dbName, 1);
    request.onupgradeneeded = (JSAny? _) {
      final db = request.result as _IdbDatabase;
      db.createObjectStore(_records);
      db.createObjectStore(_wavs);
    }.toJS;
    request.onsuccess = (JSAny? _) {
      done.complete(request.result as _IdbDatabase);
    }.toJS;
    request.onerror = (JSAny? _) {
      _opened = null;
      done.completeError(StateError('IndexedDB open: ${request.error}'));
    }.toJS;
    return done.future;
  }

  /// Runs [work] in one transaction, returning once it has COMMITTED: a
  /// request succeeding says nothing about a tab killed a moment later.
  Future<JSAny?> _run(
    List<String> stores,
    String mode,
    _IdbRequest Function(_IdbTransaction tx) work,
  ) async {
    final db = await _db();
    final done = Completer<JSAny?>();
    final tx = db.transaction(stores.map((s) => s.toJS).toList().toJS, mode);
    final request = work(tx);
    void fail(JSAny? _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: ${tx.error}'));
      }
    }

    tx.oncomplete = (JSAny? _) {
      if (!done.isCompleted) done.complete(request.result);
    }.toJS;
    tx.onerror = fail.toJS;
    tx.onabort = fail.toJS;
    return done.future;
  }

  @override
  Future<void> updateRecord(String id, String json) =>
      _run([_records], 'readwrite', (tx) {
        final records = tx.objectStore(_records);
        final current = records.get(id.toJS);
        // Placed from the read's own success, which keeps the transaction open.
        current.onsuccess = (JSAny? _) {
          if (current.result.isDefinedAndNotNull) {
            records.put(json.toJS, id.toJS);
          }
        }.toJS;
        return current;
      });

  @override
  Future<String?> getRecord(String id) async {
    final value = await _run(
      [_records],
      'readonly',
      (tx) => tx.objectStore(_records).get(id.toJS),
    );
    return (value as JSString?)?.toDart;
  }

  @override
  Future<void> putRecording(String id, String json, Uint8List wav) =>
      _run([_records, _wavs], 'readwrite', (tx) {
        tx.objectStore(_wavs).put(wav.toJS, id.toJS);
        return tx.objectStore(_records).put(json.toJS, id.toJS);
      });

  @override
  Future<Uint8List?> getWav(String id) async {
    final value = await _run(
      [_wavs],
      'readonly',
      (tx) => tx.objectStore(_wavs).get(id.toJS),
    );
    return (value as JSUint8Array?)?.toDart;
  }

  @override
  Future<void> remove(String id) => _run([_records, _wavs], 'readwrite', (tx) {
    // The WAV first, the record last, as on disk.
    tx.objectStore(_wavs).delete(id.toJS);
    return tx.objectStore(_records).delete(id.toJS);
  });

  @override
  Future<List<String>> ids() async {
    final keys = await _run(
      [_records],
      'readonly',
      (tx) => tx.objectStore(_records).getAllKeys(),
    );
    return (keys as JSArray<JSString>).toDart.map((k) => k.toDart).toList();
  }
}

PendingCallAudioRows indexedDbPendingCallAudioRows() => _IndexedDbRows();

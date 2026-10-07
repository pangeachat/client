import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;

import 'package:crypto/crypto.dart';
import 'package:matrix/matrix.dart' show Logs;
import 'package:path_provider/path_provider.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Where a finished call's recording waits between hangup and its audio half
/// confirming, so an app kill or a slow upload does not lose it.
///
/// The sidecar record is the authority; the WAV is only trusted when its length
/// AND content hash match what the sidecar promised, so a partly written file
/// is never uploaded. Statuses move persisting -> persisted -> uploaded -> sent,
/// and a sent item is deleted.
class PendingCallAudio {
  final Map<String, dynamic> json;

  const PendingCallAudio(this.json);

  static const persisting = 'persisting';
  static const persisted = 'persisted';
  static const uploaded = 'uploaded';
  static const sent = 'sent';

  /// How long an item may wait before it is given up on.
  static const ttl = Duration(days: 7);

  factory PendingCallAudio.create({
    required String audioTxnId,
    required String? transcriptTxnId,
    required String roomId,
    required String owner,
    required String? deviceId,
    required String generationId,
    required String callKey,
    required int expectedBytes,
    required String contentSha256,
    required Map<String, dynamic> audioContent,
    Map<String, dynamic>? liveTranscriptContent,
    DateTime? now,
  }) => PendingCallAudio({
    'v': 1,
    'status': persisting,
    'audio_txn_id': audioTxnId,
    'transcript_txn_id': ?transcriptTxnId,
    'room_id': roomId,
    'owner': owner,
    'device_id': ?deviceId,
    'generation_id': generationId,
    'call_key': callKey,
    'expected_bytes': expectedBytes,
    'content_sha256': contentSha256,
    // The audio half's content with an empty url; the url is filled in once
    // the upload lands, so a resume sends exactly what the live finish would.
    'audio_content': audioContent,
    // The live 45-second-chunk transcript half, frozen at hangup. What a resume
    // publishes when the app died before any transcript half was built.
    'live_transcript_content': ?liveTranscriptContent,
    'created_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
  });

  String get status => json['status'] as String;
  String get audioTxnId => json['audio_txn_id'] as String;
  String? get transcriptTxnId => json['transcript_txn_id'] as String?;
  String get roomId => json['room_id'] as String;
  String get owner => json['owner'] as String;
  String? get deviceId => json['device_id'] as String?;
  String get callKey => json['call_key'] as String;
  int get expectedBytes => json['expected_bytes'] as int;
  String get contentSha256 => json['content_sha256'] as String;
  String? get mxcUrl => json['mxc_url'] as String?;
  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int);

  Map<String, dynamic> get audioContent =>
      Map<String, dynamic>.from(json['audio_content'] as Map);

  Map<String, dynamic>? get liveTranscriptContent {
    final raw = json['live_transcript_content'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  PendingCallAudio withStatus(String status, {String? mxcUrl}) =>
      PendingCallAudio({
        ...json,
        'status': status,
        'mxc_url': ?(mxcUrl ?? this.mxcUrl),
      });

  /// Whether [json] has every field this version needs.
  static bool isWellFormed(Object? json) {
    if (json is! Map) return false;
    return json['status'] is String &&
        json['audio_txn_id'] is String &&
        json['room_id'] is String &&
        json['owner'] is String &&
        json['call_key'] is String &&
        json['expected_bytes'] is int &&
        json['content_sha256'] is String &&
        json['audio_content'] is Map &&
        json['created_at'] is int;
  }
}

/// The hex sha256 of [bytes], off the UI thread where the platform allows.
Future<String> callAudioSha256(Uint8List bytes) =>
    compute(_sha256Hex, bytes, debugLabel: 'call audio sha256');

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

abstract class CallAudioPendingStore {
  /// Writes [item] and its [wav] durably: sidecar `persisting` first, then the
  /// WAV, then the sidecar `persisted`. Returns false (and logs) on failure;
  /// never throws.
  Future<bool> persist(PendingCallAudio item, Uint8List wav);

  /// Replaces the sidecar for [item] (a status change). Atomic.
  Future<void> update(PendingCallAudio item);

  /// Deletes everything held for [audioTxnId].
  Future<void> delete(String audioTxnId);

  /// Settles whatever a crash left, applies the retention rules, and returns
  /// every item that still needs work.
  Future<List<PendingCallAudio>> recover();

  /// The WAV for [item] if it still matches its length and hash, else null.
  Future<Uint8List?> readVerified(PendingCallAudio item);

  /// Deletes every item [owner] holds. Run when that account signs out.
  Future<void> purgeOwner(String owner);
}

/// The most items, and bytes, held at once. Older items past either are
/// dropped first.
const kMaxPendingCallAudioItems = 5;
const kMaxPendingCallAudioBytes = 300 * 1024 * 1024;

const _lostKey = 'call_audio_pending.lost';

void _reportLost(String reason, String audioTxnId) {
  Logs().w('A pending call recording was dropped: $reason');
  ErrorHandler.logErrorOnce(
    key: '$_lostKey:$audioTxnId',
    e: Exception('A pending call recording was dropped: $reason'),
    data: {'reason': reason},
  );
}

/// Held in memory only. The store on the web, which has no durable file system
/// a recording could survive a reload in -- a reload there loses the item, and
/// [persist] says so in the log -- and the store tests use.
class InMemoryCallAudioPendingStore implements CallAudioPendingStore {
  final Map<String, PendingCallAudio> _items = {};
  final Map<String, Uint8List> _wavs = {};
  bool _webLossLogged = false;

  /// One per process, so a resume finds what the live finish held.
  static final InMemoryCallAudioPendingStore shared =
      InMemoryCallAudioPendingStore();

  @override
  Future<bool> persist(PendingCallAudio item, Uint8List wav) async {
    if (kIsWeb && !_webLossLogged) {
      _webLossLogged = true;
      Logs().w(
        'Call recordings wait in memory only on the web; closing or reloading '
        'the tab before the audio half lands loses it',
      );
    }
    _items[item.audioTxnId] = item.withStatus(PendingCallAudio.persisted);
    _wavs[item.audioTxnId] = wav;
    return true;
  }

  @override
  Future<void> update(PendingCallAudio item) async {
    if (!_items.containsKey(item.audioTxnId)) return;
    _items[item.audioTxnId] = item;
  }

  @override
  Future<void> delete(String audioTxnId) async {
    _items.remove(audioTxnId);
    _wavs.remove(audioTxnId);
  }

  @override
  Future<List<PendingCallAudio>> recover() async {
    final now = DateTime.now();
    for (final item in _items.values.toList()) {
      if (now.difference(item.createdAt) > PendingCallAudio.ttl) {
        _reportLost('older than its retention window', item.audioTxnId);
        await delete(item.audioTxnId);
      } else if (item.status == PendingCallAudio.sent) {
        await delete(item.audioTxnId);
      }
    }
    return _items.values.toList();
  }

  @override
  Future<Uint8List?> readVerified(PendingCallAudio item) async =>
      _wavs[item.audioTxnId];

  @override
  Future<void> purgeOwner(String owner) async {
    for (final item in _items.values.toList()) {
      if (item.owner == owner) await delete(item.audioTxnId);
    }
  }
}

/// The native store: one directory under application support, one sidecar
/// JSON plus one WAV per item, named by the sha256 of the audio half's
/// transaction id (the id itself carries user and device ids and characters a
/// file name cannot).
///
/// Every sidecar write is tmp -> fsync -> rename, so a kill mid-write leaves
/// the previous state. There is no directory fsync in Dart, so a POWER loss
/// right after a rename may lose an item; an app kill cannot.
class FileCallAudioPendingStore implements CallAudioPendingStore {
  final Future<Directory> Function() _root;

  FileCallAudioPendingStore({Future<Directory> Function()? root})
    : _root = root ?? _defaultRoot;

  static const dirName = 'pangea_call_audio_pending';

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/$dirName');
  }

  Directory? _dir;

  Future<Directory> _ensureDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = await _root();
    await dir.create(recursive: true);
    await _excludeFromBackup(dir);
    return _dir = dir;
  }

  static String nameFor(String audioTxnId) =>
      sha256.convert(utf8.encode(audioTxnId)).toString();

  File _sidecar(Directory dir, String h) => File('${dir.path}/$h.json');
  File _sidecarTmp(Directory dir, String h) => File('${dir.path}/$h.json.tmp');
  File _wav(Directory dir, String h) => File('${dir.path}/$h.wav');
  File _wavTmp(Directory dir, String h) => File('${dir.path}/$h.wav.tmp');

  Future<void> _writeSidecar(Directory dir, PendingCallAudio item) async {
    final h = nameFor(item.audioTxnId);
    final tmp = _sidecarTmp(dir, h);
    await tmp.writeAsBytes(utf8.encode(jsonEncode(item.json)), flush: true);
    await tmp.rename(_sidecar(dir, h).path);
  }

  @override
  Future<bool> persist(PendingCallAudio item, Uint8List wav) async {
    try {
      final dir = await _ensureDir();
      final h = nameFor(item.audioTxnId);
      // 1. The sidecar FIRST, carrying the length and hash the WAV must match:
      // whatever a crash leaves behind is judged against it.
      await _writeSidecar(dir, item.withStatus(PendingCallAudio.persisting));
      // 2-3. The WAV, fsynced under a temporary name, then renamed into place.
      final tmp = _wavTmp(dir, h);
      await tmp.writeAsBytes(wav, flush: true);
      await tmp.rename(_wav(dir, h).path);
      // 4. Only now does the sidecar say the recording is safely on disk.
      await _writeSidecar(dir, item.withStatus(PendingCallAudio.persisted));
      return true;
    } catch (e, s) {
      Logs().w('Could not keep the call recording on disk', e, s);
      return false;
    }
  }

  @override
  Future<void> update(PendingCallAudio item) async {
    final dir = await _ensureDir();
    // Never resurrects a deleted item: a status update for an item that is no
    // longer on disk is a no-op.
    if (!await _sidecar(dir, nameFor(item.audioTxnId)).exists()) return;
    await _writeSidecar(dir, item);
  }

  @override
  Future<void> delete(String audioTxnId) async {
    final dir = await _ensureDir();
    await _deleteName(dir, nameFor(audioTxnId));
  }

  Future<void> _deleteName(Directory dir, String h) async {
    // The WAV first, the sidecar last: a crash in between leaves a sidecar
    // with no WAV, which recovery drops; never a WAV nothing describes.
    for (final f in [
      _wav(dir, h),
      _wavTmp(dir, h),
      _sidecarTmp(dir, h),
      _sidecar(dir, h),
    ]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e, s) {
        Logs().w('Could not delete a pending call recording file', e, s);
      }
    }
  }

  Future<bool> _matches(File f, PendingCallAudio item) async {
    if (!await f.exists()) return false;
    if (await f.length() != item.expectedBytes) return false;
    final bytes = await f.readAsBytes();
    return await callAudioSha256(bytes) == item.contentSha256;
  }

  @override
  Future<List<PendingCallAudio>> recover() async {
    final Directory dir;
    try {
      dir = await _ensureDir();
    } catch (e, s) {
      Logs().w('Could not open the pending call recordings', e, s);
      return const [];
    }
    final names = <String>{};
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final base = entity.uri.pathSegments.last;
        final dot = base.indexOf('.');
        if (dot <= 0) continue;
        names.add(base.substring(0, dot));
      }
    } catch (e, s) {
      Logs().w('Could not list the pending call recordings', e, s);
      return const [];
    }

    final items = <PendingCallAudio>[];
    final now = DateTime.now();
    for (final h in names) {
      try {
        // A sidecar write that never reached its rename: the previous state
        // (if any) is the real one.
        final sidecarTmp = _sidecarTmp(dir, h);
        if (await sidecarTmp.exists()) await sidecarTmp.delete();

        final sidecar = _sidecar(dir, h);
        if (!await sidecar.exists()) {
          // The sidecar is always written first, so a WAV without one is not
          // a state this store produces.
          _reportLost('a recording with no record', h);
          await _deleteName(dir, h);
          continue;
        }
        final json = jsonDecode(await sidecar.readAsString());
        if (!PendingCallAudio.isWellFormed(json)) {
          _reportLost('an unreadable record', h);
          await _deleteName(dir, h);
          continue;
        }
        var item = PendingCallAudio(Map<String, dynamic>.from(json as Map));
        if (nameFor(item.audioTxnId) != h) {
          _reportLost('a record filed under the wrong name', h);
          await _deleteName(dir, h);
          continue;
        }
        if (now.difference(item.createdAt) > PendingCallAudio.ttl) {
          _reportLost('older than its retention window', item.audioTxnId);
          await _deleteName(dir, h);
          continue;
        }
        if (item.status == PendingCallAudio.sent) {
          // Sent, and the deletes after it did not finish.
          await _deleteName(dir, h);
          continue;
        }

        // Judged by CONTENT, not by name: either file may be the complete one
        // depending on where a crash landed.
        final wav = _wav(dir, h);
        final tmp = _wavTmp(dir, h);
        File? complete;
        if (await _matches(wav, item)) {
          complete = wav;
        } else if (await _matches(tmp, item)) {
          if (await wav.exists()) await wav.delete();
          await tmp.rename(wav.path);
          complete = wav;
        }
        if (await tmp.exists()) await tmp.delete();
        if (complete == null) {
          _reportLost('its recording was incomplete on disk', item.audioTxnId);
          await _deleteName(dir, h);
          continue;
        }
        if (item.status == PendingCallAudio.persisting) {
          item = item.withStatus(PendingCallAudio.persisted);
          await _writeSidecar(dir, item);
        }
        items.add(item);
      } catch (e, s) {
        Logs().w('Could not recover a pending call recording', e, s);
      }
    }

    // Retention: newest first, at most N items and B bytes.
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final kept = <PendingCallAudio>[];
    var bytes = 0;
    for (final item in items) {
      if (kept.length >= kMaxPendingCallAudioItems ||
          bytes + item.expectedBytes > kMaxPendingCallAudioBytes) {
        _reportLost('over the pending recordings cap', item.audioTxnId);
        await _deleteName(dir, nameFor(item.audioTxnId));
        continue;
      }
      bytes += item.expectedBytes;
      kept.add(item);
    }
    return kept;
  }

  @override
  Future<Uint8List?> readVerified(PendingCallAudio item) async {
    final dir = await _ensureDir();
    final f = _wav(dir, nameFor(item.audioTxnId));
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    if (bytes.length != item.expectedBytes ||
        await callAudioSha256(bytes) != item.contentSha256) {
      return null;
    }
    return bytes;
  }

  @override
  Future<void> purgeOwner(String owner) async {
    final Directory dir;
    try {
      dir = await _ensureDir();
    } catch (e, s) {
      Logs().w('Could not open the pending call recordings to purge', e, s);
      return;
    }
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final json = jsonDecode(await entity.readAsString());
          if (json is Map && json['owner'] == owner) {
            final base = entity.uri.pathSegments.last;
            await _deleteName(dir, base.substring(0, base.indexOf('.')));
          }
        } catch (e, s) {
          Logs().w('Could not read a pending call recording to purge', e, s);
        }
      }
    } catch (e, s) {
      Logs().w('Could not purge the pending call recordings', e, s);
    }
  }

  static const _backupChannel = MethodChannel('chat.pangea/backup_exclusion');

  /// Keeps the recordings out of the device backup. Android: the app opts out
  /// of backup entirely (`allowBackup="false"`). iOS: application support IS
  /// backed up, so the directory is flagged excluded; best-effort, logged.
  static Future<void> _excludeFromBackup(Directory dir) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _backupChannel.invokeMethod<bool>('exclude', dir.path);
    } catch (e, s) {
      Logs().w('Could not exclude call recordings from the backup', e, s);
    }
  }
}

/// The store this platform uses: on disk where there is a file system, in
/// memory on the web.
CallAudioPendingStore pendingCallAudioStoreForPlatform() =>
    kIsWeb ? InMemoryCallAudioPendingStore.shared : _sharedFileStore;

final FileCallAudioPendingStore _sharedFileStore = FileCallAudioPendingStore();

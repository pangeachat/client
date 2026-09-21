import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart' show Logs;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';

/// Sends one already-built transcript half to the homeserver and returns the
/// event id it confirmed, or null when the send did not durably land.
///
/// Mirrors `Room.sendEvent`'s own contract exactly -- null (never a throw) is
/// how the SDK reports a send the server did not accept -- so a null result is
/// "did not land, keep it" and a non-null one is "landed, drop it". The room is
/// named per call because a replay at launch resends halves of calls across
/// many rooms from one place, and a room the client no longer knows yields
/// null, the same as an unconfirmed send.
typedef PendingTranscriptSend =
    Future<String?> Function(
      String roomId,
      String txnId,
      Map<String, dynamic> content,
    );

/// The raw send [CallTranscriptOutbox.guard] wraps: the room's own
/// `sendEvent`, returning the event id or null on a send that did not land.
typedef RawTranscriptSend =
    Future<String?> Function(Map<String, dynamic> content, String txnId);

/// Where a transcript half waits between the hangup-time publish and the
/// homeserver confirming it, so a publish the app never got to finish -- it
/// backgrounded or was killed at hangup -- is not lost but replayed on the next
/// launch or foreground.
///
/// The sibling of [CallAudioUploadStateStore] for the transcript half: durable
/// past the Dart isolate, keyed by the deterministic transaction id, and
/// best-effort on every path -- a store that cannot be read or written is
/// treated as empty rather than as a reason to fail a publish. One key per
/// transaction id, the same `(call key, sender, device)` triple the half's txn
/// id is built from, so a replay reproduces the identical event and the server
/// collapses it against a copy that did land.
abstract class PendingCallTranscriptStore {
  /// Every well-formed pending half currently stored. A malformed or unrelated
  /// record is skipped, never thrown on -- a durable cache that cannot be
  /// trusted is no worse than an empty one, on the same terms
  /// [CallAudioUploadStateStore] treats its own unreadable record.
  Future<List<Map<String, dynamic>>> readAll();

  /// Persists [record] under [txnId], replacing whatever was stored before.
  Future<void> write(String txnId, Map<String, dynamic> record);

  /// Drops the pending half for [txnId] once the homeserver has confirmed it
  /// (or once it is otherwise known no longer to need replaying).
  Future<void> remove(String txnId);
}

/// The in-memory store, for tests and for a default that touches no disk. A
/// half only survives the process in the [SharedPreferencesPendingCallTranscriptStore],
/// which is what a real call wires; this one keeps the same shape so the logic
/// above it is exercised without a platform.
class InMemoryPendingCallTranscriptStore implements PendingCallTranscriptStore {
  final Map<String, Map<String, dynamic>> _byTxnId = {};

  @override
  Future<List<Map<String, dynamic>>> readAll() async =>
      _byTxnId.values.map(Map<String, dynamic>.of).toList();

  @override
  Future<void> write(String txnId, Map<String, dynamic> record) async {
    _byTxnId[txnId] = Map.of(record);
  }

  @override
  Future<void> remove(String txnId) async {
    _byTxnId.remove(txnId);
  }
}

/// The durable half: `SharedPreferences`, the same store [CallBreadcrumb] and
/// [SharedPreferencesCallAudioUploadStateStore] use for the same reason -- a
/// record that has to outlive the Dart isolate, not merely the loop that wrote
/// it. One key per transaction id, prefixed so a scan for pending halves reads
/// ours and only ours.
class SharedPreferencesPendingCallTranscriptStore
    implements PendingCallTranscriptStore {
  const SharedPreferencesPendingCallTranscriptStore();

  static const _prefix = 'pangea.call_transcript.pending.';

  static String _keyFor(String txnId) => '$_prefix$txnId';

  @override
  Future<List<Map<String, dynamic>>> readAll() async {
    try {
      final store = await SharedPreferences.getInstance();
      final records = <Map<String, dynamic>>[];
      for (final key in store.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        try {
          // Inside the per-record try, alongside the decode: a prefixed key
          // holding a NON-string value (a future version, or corruption, that
          // wrote an int or bool there) makes `getString` itself throw. Outside
          // this try that throw would reach the outer catch and discard every
          // valid record already collected -- and, since the bad key stays,
          // every later read would fail the same way. One bad key must cost
          // only itself, so both the read and the decode are guarded here.
          final raw = store.getString(key);
          if (raw == null) continue;
          final json = jsonDecode(raw);
          // Somebody else's bytes, in principle -- a future app version writing
          // a shape this one does not expect, or a value corrupted on disk.
          // Skipped rather than thrown on, so one bad record cannot take the
          // whole replay down with it.
          if (json is! Map<String, dynamic>) continue;
          // The KEY is the authoritative identity, not the record's own
          // `txn_id` field. A record is dropped from the store by
          // `remove(record['txn_id'])`, so a record whose declared `txn_id`
          // disagrees with the key it is stored under would, once sent, delete
          // a DIFFERENT key -- a crafted or corrupted entry declaring another
          // account's transaction id could make one flush erase that account's
          // genuine unsent half. Rejected on read, so a confirmed send can only
          // ever remove the exact key its record came from.
          if (json['txn_id'] != key.substring(_prefix.length)) {
            Logs().w(
              'Skipping a pending call transcript whose txn id does not match '
              'its key',
            );
            continue;
          }
          records.add(json);
        } catch (e, s) {
          Logs().w('Skipping an unreadable pending call transcript', e, s);
        }
      }
      return records;
    } catch (e, s) {
      Logs().w('Could not read the persisted call transcripts', e, s);
      return const [];
    }
  }

  @override
  Future<void> write(String txnId, Map<String, dynamic> record) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(_keyFor(txnId), jsonEncode(record));
    } catch (e, s) {
      Logs().w('Could not persist the pending call transcript', e, s);
    }
  }

  @override
  Future<void> remove(String txnId) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.remove(_keyFor(txnId));
    } catch (e, s) {
      Logs().w('Could not clear the pending call transcript', e, s);
    }
  }
}

/// A durable outbox for this device's own call-transcript half.
///
/// The recording-based half is published POST-hangup, after a seconds-long
/// speech-to-text round trip on the whole recording. On mobile the app
/// backgrounds the instant the user walks away, and that late publish is
/// dropped -- the half was BUILT (the STT returned) but never landed. This
/// remembers the built event BEFORE the network send and drops it only once the
/// homeserver confirms it, so a publish the app never finished is replayed on
/// the next launch or foreground. The deterministic transaction id makes the
/// replay safe: a half that did land is collapsed server-side, so a resend is a
/// no-op.
///
/// This carries none of the delicate call lifecycle -- it stores the finished
/// event's bytes and replays them, needing only a room to send into -- so it
/// survives an app KILL, not merely a backgrounding, and cannot regress a live
/// call.
class CallTranscriptOutbox {
  final PendingCallTranscriptStore store;

  // Not const: [_inFlight] is mutable per-instance state (the one-flush-at-a-
  // time guard). The store default is still a const instance.
  CallTranscriptOutbox({
    this.store = const SharedPreferencesPendingCallTranscriptStore(),
  });

  /// The replay currently running, or null when none is. A second [flush] while
  /// one is in flight joins it rather than starting a competing pass.
  Future<void>? _inFlight;

  /// Persists the built half BEFORE it goes on the wire. Best-effort: a store
  /// that cannot be written costs only the cross-restart guarantee, never the
  /// send itself, so nothing here throws.
  ///
  /// [owner] is the user id that recorded this half. The store is one durable
  /// area shared by every account signed in on this device, so the owner is
  /// kept with the record and [flush] replays only its owner's halves -- a
  /// second account must never publish or delete a half that is not its own.
  Future<void> remember(
    String roomId,
    String txnId,
    String? owner,
    Map<String, dynamic> content,
  ) => store.write(txnId, {
    'room_id': roomId,
    'txn_id': txnId,
    'owner': owner,
    'content': content,
  });

  /// Drops the pending half once the homeserver has confirmed it.
  Future<void> forget(String txnId) => store.remove(txnId);

  /// Wraps [rawSend] so the half is durably remembered before the network
  /// attempt and dropped only once the send confirms it.
  ///
  /// A send that THROWS (the dropped-at-hangup case) leaves the record and lets
  /// the throw propagate, so the caller's own in-session retry still runs and
  /// the record is there for a later launch if every retry is dropped too. A
  /// send that returns null (the server did not confirm) leaves the record as
  /// well. Only a confirmed event id drops it.
  TranscriptSender guard(
    String roomId,
    String? owner,
    RawTranscriptSend rawSend,
  ) => (content, txnId) async {
    await remember(roomId, txnId, owner, content);
    final eventId = await rawSend(content, txnId);
    if (eventId != null) await forget(txnId);
  };

  /// Replays every half [owner] still has waiting, dropping each the moment its
  /// send confirms. Called on the next launch or foreground.
  ///
  /// [owner] is the user id of the account doing the replay. Only that account's
  /// own halves are replayed: the store is shared by every account on the
  /// device, and a second account resending -- and then deleting -- a half that
  /// is not its own would both publish one account's speech under another and
  /// lose the real owner's record. A record with no matching owner is left for
  /// the account that wrote it.
  ///
  /// A half whose send throws or does not confirm (an unknown room, a server
  /// that did not accept it) is KEPT for the next flush, never dropped on a
  /// failure. One half throwing does not strand the rest -- each is a different
  /// call and is tried independently, mirroring the merge coordinator's own
  /// per-trigger replay.
  ///
  /// One replay at a time within this outbox: a second call while one is
  /// already running joins the in-flight pass rather than reading the same
  /// pending records and sending each a second time (the first-sync and
  /// foreground triggers can arrive together). Mirrors
  /// `CallAudioRecorder.finish`'s own single-flight latch; `CallService` guards
  /// its triggers too, so this is the module honouring the contract itself.
  Future<void> flush(PendingTranscriptSend send, {required String? owner}) {
    return _inFlight ??= _flush(
      send,
      owner: owner,
    ).whenComplete(() => _inFlight = null);
  }

  Future<void> _flush(
    PendingTranscriptSend send, {
    required String? owner,
  }) async {
    final pending = await store.readAll();
    for (final record in pending) {
      final roomId = record['room_id'];
      final txnId = record['txn_id'];
      final content = record['content'];
      // A record missing the fields a resend needs can never be sent, so it is
      // skipped rather than replayed forever. It is left on disk rather than
      // deleted, on the same conservative terms [readAll] already skips a shape
      // it does not recognise: a value this version cannot use may be one a
      // later version can.
      if (roomId is! String || txnId is! String || content is! Map) continue;
      // Not this account's half: another signed-in account wrote it, and only
      // its owner may resend or drop it (see the method docs). Left untouched.
      //
      // A null [owner] is NOT an identity that can own anything: a caller with
      // no user id (a client not fully signed in) must claim nothing, and it
      // must never match an ownerless record (`null == null`) and delete it.
      // So a null caller owner skips every record, and a record with a null or
      // mismatched owner is skipped by a real caller.
      if (owner == null || record['owner'] != owner) continue;
      try {
        final eventId = await send(
          roomId,
          txnId,
          Map<String, dynamic>.from(content),
        );
        if (eventId != null) await store.remove(txnId);
      } catch (e, s) {
        // Kept for the next flush -- a transient failure (offline, a room not
        // yet loaded) resolves on a later launch, and the deterministic txn id
        // means the eventual resend cannot become a duplicate.
        Logs().w('Replaying a pending call transcript failed', e, s);
      }
    }
  }
}

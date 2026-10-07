import 'dart:async';

import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';
import 'package:fluffychat/routes/chat/calls/call_half_in_flight.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_outbox.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart'
    show CallAudioUploader;

/// Whether THIS device's own half of one call is already in the room.
///
/// True when found, false when the read finished without finding it, and null
/// when it could not be concluded -- the read failed, or stopped at the page
/// ceiling. Null is never "absent": a caller that would resend on null could
/// post a duplicate half, so null always means keep and send nothing.
///
/// "Own" is (event type, sender, device): a peer half this account wrote for
/// someone else (`spoken_by`, the whole-call transcriber's) is not this
/// device's own half and does not count.
Future<bool?> ownCallHalfInRoom({
  required RelationsFetcher fetch,
  required String roomId,
  required String callKey,
  required String relType,
  required String senderId,
  required String? deviceId,
}) async {
  final device = CallTranscriptContent.usableDeviceId(deviceId);
  try {
    String? from;
    for (var page = 0; page < kMaxRelationPages; page++) {
      final result = await fetch(
        roomId: roomId,
        eventId: callKey,
        relType: relType,
        from: from,
      );
      for (final event in result.chunk) {
        if (event.type != relType || event.senderId != senderId) continue;
        final content = event.content;
        if (content['call_key'] != callKey) continue;
        if (CallTranscriptContent.usableDeviceId(content['device_id']) !=
            device) {
          continue;
        }
        if (CallTranscriptContent.usableSpokenBy(content['spoken_by']) !=
            null) {
          continue;
        }
        return true;
      }
      from = result.nextBatch;
      if (from == null) return false;
    }
    Logs().w('Reading the room for an own call half stopped at its ceiling');
    return null;
  } catch (e, s) {
    Logs().w('Could not read the room for an own call half', e, s);
    return null;
  }
}

/// Sends one event of [type] into [roomId] under [txnId], returning the event
/// id or null when it did not durably land (including an unknown room).
typedef CallHalfRoomSend =
    Future<String?> Function(
      String roomId,
      String type,
      Map<String, dynamic> content,
      String txnId,
    );

/// Picks up the call halves a previous process -- or a parked live finish --
/// left on disk, and finishes them. Never credits: crediting happened (or was
/// accepted lost) at hangup.
///
/// For each durable item this account owns, in order:
///
/// 1. The transcript half, only when nobody built one: no outbox record and
///    not in the room. Then the live half frozen at hangup is published, through
///    the outbox so it is durable from here on. A room that cannot be read
///    defers the WHOLE item to the next trigger.
/// 2. The audio half: read the room; found means the send landed late, so the
///    record is closed without sending. Otherwise upload (unless the record
///    already has its url), send the same transaction id, close the record.
///
/// Every half is claimed in [CallHalfInFlight] for its scope, every await is
/// bounded, and a deadline parks the item for the next trigger.
class CallHalfResumer {
  final CallAudioPendingStore store;
  final RelationsFetcher fetch;
  final CallAudioUploader upload;
  final CallHalfRoomSend send;
  final CallTranscriptOutbox outbox;

  /// Called once an audio half lands, so the merge of both halves can start.
  final void Function(
    String roomId,
    String callKey,
    String owner,
    String? device,
  )?
  onAudioPosted;

  final Duration uploadSessionBudget;
  final Duration Function(int bytes) uploadAttemptBound;

  CallHalfResumer({
    required this.store,
    required this.fetch,
    required this.upload,
    required this.send,
    required this.outbox,
    this.onAudioPosted,
    this.uploadSessionBudget = kCallAudioUploadSessionBudget,
    this.uploadAttemptBound = callAudioUploadAttemptBound,
  });

  Future<void>? _inFlight;

  /// One pass over everything [owner] has waiting. Concurrent calls join.
  Future<void> resume({required String? owner}) =>
      _inFlight ??= _resume(owner).whenComplete(() => _inFlight = null);

  Future<void> _resume(String? owner) async {
    if (owner == null) return;
    final items = await store.recover();
    if (items.isEmpty) return;
    final budget = CallHalfBudget(uploadSessionBudget);
    for (final item in items) {
      if (item.owner != owner) continue;
      try {
        final proceed = await _resumeTranscript(item);
        if (!proceed) continue;
        await _resumeAudio(item, budget);
      } catch (e, s) {
        Logs().w('Resuming a pending call half failed; kept for later', e, s);
      }
    }
  }

  /// Returns whether the audio half may go ahead this pass.
  Future<bool> _resumeTranscript(PendingCallAudio item) async {
    final txnId = item.transcriptTxnId;
    final content = item.liveTranscriptContent;
    if (txnId == null || content == null) return true;
    final pending = await outbox.store.readAll();
    // Already built: the outbox owns its replay.
    if (pending.any((r) => r['txn_id'] == txnId)) return true;
    final claim = CallHalfInFlight.claim(txnId);
    // Someone in this process is publishing it right now.
    if (claim == null) return true;
    try {
      final found = await raceBounded(
        ownCallHalfInRoom(
          fetch: fetch,
          roomId: item.roomId,
          callKey: item.callKey,
          relType: CallTranscriptContent.relType,
          senderId: item.owner,
          deviceId: item.deviceId,
        ),
        deadline: kCallHalfNetworkDeadline,
        step: 'read the room for the transcript half',
      );
      if (found == null) return false;
      if (found) return true;
      Logs().i(
        'Publishing the live transcript half a killed call never published',
      );
      final attempt = AttemptToken();
      try {
        await attempt.run(
          () => raceBounded(
            outbox.guard(
              item.roomId,
              item.owner,
              (c, t) => send(item.roomId, CallTranscriptContent.relType, c, t),
            )(content, txnId),
            deadline: kCallHalfNetworkDeadline,
            step: 'send the transcript half',
          ),
        );
      } finally {
        attempt.live = false;
      }
      return true;
    } finally {
      CallHalfInFlight.release(claim);
    }
  }

  Future<void> _resumeAudio(
    PendingCallAudio item,
    CallHalfBudget budget,
  ) async {
    final claim = CallHalfInFlight.claim(item.audioTxnId);
    if (claim == null) return;
    try {
      final found = await raceBounded(
        ownCallHalfInRoom(
          fetch: fetch,
          roomId: item.roomId,
          callKey: item.callKey,
          relType: CallAudioContent.relType,
          senderId: item.owner,
          deviceId: item.deviceId,
        ),
        deadline: kCallHalfNetworkDeadline,
        step: 'read the room for the audio half',
      );
      if (found == null) return;
      if (found) {
        // The send landed after its process gave up on it.
        await _close(item);
        return;
      }

      var current = item;
      var url = current.status == PendingCallAudio.uploaded
          ? current.mxcUrl
          : null;
      if (url == null) {
        final wav = await raceBounded(
          store.readVerified(current),
          deadline: const Duration(seconds: 30),
          step: 'read the recording',
        );
        if (wav == null) {
          Logs().w('A pending call recording failed its check; dropped');
          await boundedLocal(store.delete(current.audioTxnId), 'drop damaged');
          return;
        }
        if (budget.remaining == Duration.zero) {
          throw const CallHalfParked('upload budget spent');
        }
        final attempt = AttemptToken();
        try {
          final uploadFuture = upload(
            wav,
            filename: 'call_audio.wav',
            contentType: 'audio/wav',
          );
          // Log-only: an upload that lands after its attempt was abandoned is
          // an orphan, and nothing here writes on its behalf.
          unawaited(
            uploadFuture.then((landed) {
              if (!attempt.live) {
                Logs().w(
                  'A resumed call-audio blob at $landed is now an orphan no '
                  'event will reference',
                );
              }
            }, onError: (Object _, StackTrace _) {}),
          );
          final landed = await raceBounded(
            uploadFuture,
            deadline: budget.cap(uploadAttemptBound(wav.length)),
            step: 'upload',
            attempt: attempt,
          );
          url = landed.toString();
        } finally {
          attempt.live = false;
        }
        current = current.withStatus(PendingCallAudio.uploaded, mxcUrl: url);
        await boundedLocal(store.update(current), 'mark uploaded');
      }

      final content = current.audioContent..['url'] = url;
      final eventId = await raceBounded(
        send(
          current.roomId,
          CallAudioContent.relType,
          content,
          current.audioTxnId,
        ),
        deadline: budget.cap(kCallHalfNetworkDeadline),
        step: 'send the audio half',
      );
      if (eventId == null) {
        Logs().w('A resumed call-audio half did not land; kept for later');
        return;
      }
      await _close(current);
      onAudioPosted?.call(
        current.roomId,
        current.callKey,
        current.owner,
        current.deviceId,
      );
    } finally {
      CallHalfInFlight.release(claim);
    }
  }

  Future<void> _close(PendingCallAudio item) async {
    await boundedLocal(
      store.update(item.withStatus(PendingCallAudio.sent)),
      'mark sent',
    );
    await boundedLocal(store.delete(item.audioTxnId), 'delete sent');
  }
}

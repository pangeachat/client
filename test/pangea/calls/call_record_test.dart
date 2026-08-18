import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'call_transcript_sink_test.dart' show chunk, silent, spokenWord;

void main() {
  late List<Map<String, dynamic>> written;
  late List<String> txids;
  late List<({String eventId, int uses, String lang})> recorded;

  setUp(() {
    written = [];
    txids = [];
    recorded = [];
  });

  Future<CallTranscriptSink> sinkWith(
    SpeechToTextResponseModel Function() respond, {
    int chunks = 1,
  }) async {
    final sink = CallTranscriptSink(
      userL1: 'en',
      userL2: 'es',
      transcribe: (_) async => respond(),
    );
    for (var i = 0; i < chunks; i++) {
      await sink.deliver(chunk(i));
    }
    return sink;
  }

  CallRecord record(
    CallTranscriptSink transcripts, {
    String? eventId = '\$call',
    Object? writeError,
    Object? analyticsError,
  }) => CallRecord(
    roomId: '!r:server',
    transcripts: transcripts,
    sendEvent: (content, txid) async {
      txids.add(txid);
      if (writeError != null) throw writeError;
      written.add(content);
      return eventId;
    },
    analytics: (id, uses, lang) async {
      if (analyticsError != null) throw analyticsError;
      recorded.add((eventId: id, uses: uses.length, lang: lang));
    },
  );

  test('writes the call to the room and records what was said', () async {
    final r = record(await sinkWith(() => spokenWord('hola')));
    await r.finish(duration: const Duration(seconds: 92), video: false);

    expect(written, hasLength(1));
    expect(written.single['msgtype'], PangeaEventTypes.call);
    expect(written.single['duration_ms'], 92000);
    expect(written.single['video'], isFalse);

    expect(recorded, hasLength(1));
    expect(recorded.single.eventId, '\$call');
    expect(recorded.single.lang, 'es');
    expect(recorded.single.uses, greaterThan(0));
  });

  test('a missed call appears in the timeline but credits nothing', () async {
    // Every calling product shows a missed call. Someone who was away would
    // otherwise have no idea anyone had tried to reach them — and there is no
    // conversation to credit, because nothing was said to anyone.
    final r = record(await sinkWith(() => spokenWord('hola')));
    await r.finish(
      duration: const Duration(seconds: 45),
      video: false,
      answered: false,
    );

    expect(written, hasLength(1));
    expect(written.single['answered'], isFalse);
    expect(recorded, isEmpty, reason: 'nobody was there to talk to');
  });

  test('an answered call is recorded as answered', () async {
    final r = record(await sinkWith(() => spokenWord('hola')));
    await r.finish(duration: const Duration(seconds: 45), video: false);

    expect(written.single['answered'], isTrue);
    expect(recorded, hasLength(1));
  });

  test('a silent call still appears in the timeline', () async {
    // The call happened. A learner looking back should see it whether or not it
    // earned them anything.
    final r = record(await sinkWith(() => silent));
    await r.finish(duration: const Duration(seconds: 30), video: true);

    expect(written, hasLength(1));
    expect(written.single['video'], isTrue);
    expect(recorded, isEmpty);
  });

  test('finishing twice writes one entry and credits once', () async {
    // A hangup racing a disconnect reaches here twice; the second must not post
    // a second entry or credit the same words again.
    final r = record(await sinkWith(() => spokenWord('hola')));
    await r.finish(duration: const Duration(seconds: 10), video: false);
    await r.finish(duration: const Duration(seconds: 10), video: false);

    expect(written, hasLength(1));
    expect(recorded, hasLength(1));
  });

  test('nothing is credited when the call could not be written', () async {
    // An unanchored use cannot be traced back to the call that earned it.
    final r = record(
      await sinkWith(() => spokenWord('hola')),
      writeError: StateError('room rejected the event'),
    );
    await r.finish(duration: const Duration(seconds: 10), video: false);

    expect(written, isEmpty);
    expect(recorded, isEmpty);
  });

  test('a transient write failure is retried without another caller', () async {
    // Both production callers are the same hangup and the screen is gone
    // afterwards, so nothing calls back later. A blip at hangup would otherwise
    // cost the whole call's credit.
    final transcripts = await sinkWith(() => spokenWord('hola'));
    var attempts = 0;
    final r = CallRecord(
      roomId: '!r:server',
      transcripts: transcripts,
      sendEvent: (content, txid) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        written.add(content);
        return '\$call';
      },
      analytics: (id, uses, lang) async =>
          recorded.add((eventId: id, uses: uses.length, lang: lang)),
    );

    await r.finish(duration: const Duration(seconds: 10), video: false);

    expect(attempts, 2, reason: 'it tried again on its own');
    expect(written, hasLength(1), reason: 'and wrote the call exactly once');
    expect(recorded, hasLength(1));
  });

  test('a write that keeps failing gives up rather than looping', () async {
    final transcripts = await sinkWith(() => spokenWord('hola'));
    var attempts = 0;
    final r = CallRecord(
      roomId: '!r:server',
      transcripts: transcripts,
      sendEvent: (_, _) async {
        attempts++;
        throw StateError('still offline');
      },
      analytics: (id, uses, lang) async =>
          recorded.add((eventId: id, uses: uses.length, lang: lang)),
    );

    await r.finish(duration: const Duration(seconds: 10), video: false);

    expect(attempts, lessThanOrEqualTo(3));
    expect(recorded, isEmpty);
  });

  test('a failed credit is retried against the same call event', () async {
    // The event write and the credit fail independently. Marking the whole
    // record done when only the event landed would lose the learner's analytics
    // permanently — and a retry must not post a second call to the timeline.
    final transcripts = await sinkWith(() => spokenWord('hola'));
    var creditAttempts = 0;
    final r = CallRecord(
      roomId: '!r:server',
      transcripts: transcripts,
      sendEvent: (content, txid) async {
        written.add(content);
        return '\$call';
      },
      analytics: (id, uses, lang) async {
        creditAttempts++;
        if (creditAttempts == 1) throw StateError('analytics unavailable');
        recorded.add((eventId: id, uses: uses.length, lang: lang));
      },
    );

    await r.finish(duration: const Duration(seconds: 10), video: false);

    expect(creditAttempts, 2, reason: 'the credit was retried');
    expect(recorded, hasLength(1));
    expect(
      written,
      hasLength(1),
      reason: 'and the retry reused the call already in the timeline',
    );
  });

  test('nothing is credited when the room returns no event id', () async {
    final r = record(await sinkWith(() => spokenWord('hola')), eventId: null);
    await r.finish(duration: const Duration(seconds: 10), video: false);
    expect(recorded, isEmpty);
  });

  test('a failed analytics write does not throw out of the hangup', () async {
    final r = record(
      await sinkWith(() => spokenWord('hola')),
      analyticsError: StateError('analytics unavailable'),
    );
    await expectLater(
      r.finish(duration: const Duration(seconds: 10), video: false),
      completes,
    );
    expect(written, hasLength(1), reason: 'the call is still in the timeline');
  });

  test('a longer call credits more than a shorter one', () async {
    // Three chunks of the same word must credit three times what one does — the
    // batch is the union of the chunks, not whichever chunk happened to be read.
    final one = record(await sinkWith(() => spokenWord('hola')));
    await one.finish(duration: const Duration(seconds: 30), video: false);
    final single = recorded.single.uses;

    recorded.clear();
    written.clear();

    final three = record(await sinkWith(() => spokenWord('hola'), chunks: 3));
    await three.finish(duration: const Duration(seconds: 90), video: false);

    expect(recorded.single.uses, single * 3);
  });
  group('which side writes the call', () {
    test(
      'the answering side credits its speech without posting a call',
      () async {
        // Both sides run the same teardown. If both wrote, every two-person call
        // would leave two identical cards in the conversation.
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.finish(
          duration: const Duration(seconds: 30),
          video: false,
          writeTimelineEvent: false,
          anchorEventId: '\$notification',
        );

        expect(written, isEmpty, reason: 'the caller posts the call, not us');
        expect(recorded, hasLength(1));
        expect(
          recorded.single.eventId,
          '\$notification',
          reason: 'the answering side anchors to the call it was rung with',
        );
      },
    );

    test('the placing side still writes the call', () async {
      final r = record(await sinkWith(() => spokenWord('hola')));
      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        writeTimelineEvent: true,
      );

      expect(written, hasLength(1));
      expect(recorded.single.eventId, '\$call');
    });

    test(
      'an answering side with nothing to anchor to credits nothing',
      () async {
        // Rather than crediting speech against an event that does not exist,
        // which could not be traced back to the call that earned it.
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.finish(
          duration: const Duration(seconds: 30),
          video: false,
          writeTimelineEvent: false,
        );

        expect(written, isEmpty);
        expect(recorded, isEmpty);
      },
    );

    test(
      'the written call carries a readable fallback for other clients',
      () async {
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.finish(duration: const Duration(seconds: 92), video: false);
        expect(written.single['body'], 'Voice call (1:32)');
      },
    );

    test('a missed call says so in its fallback', () async {
      final r = record(await sinkWith(() => silent));
      await r.finish(duration: Duration.zero, video: false, answered: false);
      expect(written.single['body'], 'Missed call');
    });
  });
  group('who is recorded as the caller', () {
    test('is stated in the event, not left to be inferred', () async {
      // Which side writes is decided by comparing user ids so exactly one card
      // exists when both people call at once — and that side is not always the
      // caller, so direction cannot be read from who wrote it.
      final r = record(await sinkWith(() => spokenWord('hola')));
      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callerId: '@teacher:server',
      );

      expect(written.single['caller'], '@teacher:server');
    });

    test('is left out when there is nobody to name', () async {
      final r = record(await sinkWith(() => spokenWord('hola')));
      await r.finish(duration: const Duration(seconds: 30), video: false);
      expect(written.single.containsKey('caller'), isFalse);
    });
  });
  test('every attempt at writing the call reuses one transaction id', () async {
    // A send whose response is lost may already have been persisted. Retrying
    // with a fresh id would post the call a second time; reusing it makes the
    // homeserver hand back the event the first attempt created.
    var attempts = 0;
    final transcripts = await sinkWith(() => spokenWord('hola'));
    final r = CallRecord(
      roomId: '!r:server',
      transcripts: transcripts,
      sendEvent: (content, txid) async {
        txids.add(txid);
        attempts++;
        if (attempts == 1) throw StateError('response lost');
        written.add(content);
        return '\$call';
      },
      analytics: (id, uses, lang) async =>
          recorded.add((eventId: id, uses: uses.length, lang: lang)),
    );

    await r.finish(duration: const Duration(seconds: 5), video: false);

    expect(attempts, greaterThan(1), reason: 'the write was retried');
    expect(txids.toSet(), hasLength(1));
  });
}

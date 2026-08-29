import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/call_upload_gate.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'call_transcript_sink_test.dart' show chunk, silent, spokenWord;

const kDur = Duration(seconds: 30);

/// A sink whose reported content CHANGES on every read.
///
/// Nothing real does this, and that is the point: a retry that re-reads the
/// sink is indistinguishable from one that resends a snapshot unless the two
/// reads can differ. The deterministic transaction id collapses a RESEND, so
/// sending different content under the same id is not a resend at all -- the
/// server keeps whichever arrived first and the rest is silently discarded.
class _ShiftingSink extends CallTranscriptSink {
  _ShiftingSink()
    : super(
        userL1: 'en',
        userL2: 'es',
        transcribe: (_) async => spokenWord('hola'),
      );

  int reads = 0;

  @override
  List<TranscriptSegment> get segments {
    reads++;
    return [TranscriptSegment('read $reads')];
  }
}

void main() {
  // The sinks below take the process-wide upload gate. One test here hands a
  // chunk to a transcriber that never answers and never bounds the wait, so it
  // keeps a permit for the life of the isolate; without this the cap would be
  // one lower for every test after it, and the failure would land on whichever
  // test happened to run last.
  setUp(CallUploadGate.resetShared);

  late List<Map<String, dynamic>> written;
  late List<String> txids;
  late List<({String eventId, int uses, String lang})> recorded;

  /// What the transcript publisher was handed, if a test wired one up. Reset
  /// per test like the others: a shared collector let one test see another's
  /// halves, so three of these passed or failed on ordering rather than on
  /// what the code did.
  late List<
    ({
      String callKey,
      int segments,
      int captured,
      int transcribed,
      int lost,
      bool drained,
    })
  >
  published;

  /// Every publish ATTEMPT, by the words it carried. Distinct from [published],
  /// which records only the ones that landed.
  late List<List<String>> publishAttempts;

  setUp(() {
    written = [];
    txids = [];
    recorded = [];
    published = [];
    publishAttempts = [];
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
    bool withPublisher = false,
    Object? publishError,
    int publishFailures = 0,
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
    publishTranscript: !withPublisher
        ? null
        : ({
            required String callKey,
            required List<TranscriptSegment> segments,
            required int chunksCaptured,
            required int chunksTranscribed,
            required int chunksLost,
            required int chunksSuppressed,
            required bool captureRefused,
            required bool drainComplete,
            String? langCode,
          }) async {
            publishAttempts.add(segments.map((s) => s.text).toList());
            if (publishError != null) throw publishError;
            if (publishAttempts.length <= publishFailures) {
              throw Exception('transient');
            }
            published.add((
              callKey: callKey,
              segments: segments.length,
              captured: chunksCaptured,
              transcribed: chunksTranscribed,
              lost: chunksLost,
              drained: drainComplete,
            ));
          },
  );

  group('publishing the transcript half', () {
    test('publishes once, anchored to the call key', () async {
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
      );
      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: '\$anchor',
      );

      expect(published, hasLength(1));
      expect(published.single.callKey, '\$anchor');
      expect(published.single.segments, greaterThan(0));
    });

    test('does not publish twice when the credit is retried', () async {
      // The guard is only REACHABLE when a first finish did not credit: a
      // credited record returns before the publish path. An analytics store
      // that refuses puts the record back in play, and that second pass must
      // not write the learner's words a second time.
      //
      // An earlier version of this test simply called finish twice on a
      // successful record. That could not fail: the second call returned at
      // the _credited check and never reached the guard at all.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
        analyticsError: const CallAnalyticsNotStored('the store was closed'),
      );
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');

      expect(published, hasLength(1));
    });

    test('publishes even when the card could not be written', () async {
      // The transcript needs only the anchor. Coupling it to the card's event
      // id meant a failed write cost the words as well, though nothing about
      // publishing depends on the card existing.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
        writeError: StateError('the server said no'),
      );
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');

      expect(published, hasLength(1));
      expect(recorded, isEmpty, reason: 'nothing to credit against');
    });

    test('publishes on a later finish that finally has the anchor', () async {
      // The ordinary lifecycle can credit first and learn the call key second.
      // Behind the _credited guard the transcript was then never published at
      // all -- the credit was right and the words were silently lost.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
      );
      await r.finish(duration: kDur, video: false);
      expect(published, isEmpty, reason: 'no anchor yet');

      await r.finish(duration: kDur, video: false, callKey: '\$anchor');
      expect(published, hasLength(1));
    });

    test('an abandoned drain is reported, not smoothed over', () async {
      // drainComplete exists to stop a half claiming to be everything somebody
      // said. Hard-coding it true passed every other test here, because none of
      // them could reach a drain that gave up.
      final sink = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        settleWithin: Duration.zero,
        transcribe: (_) => Completer<SpeechToTextResponseModel>().future,
      );
      unawaited(sink.deliver(chunk(0)));
      // The capture service closes the sink before the record finishes, so the
      // record reads a settled answer rather than the optimistic default. The
      // order matters and this mirrors it.
      expect(await sink.close(), isFalse);

      final r = record(sink, withPublisher: true);
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');

      expect(published.single.drained, isFalse);
    });

    test('a half that exhausted its retries can still publish later', () async {
      // Belt and braces on top of the in-finish retry, which is the one that
      // matters: in production finish() runs once per call behind a latch, so
      // "a later finish" is not a mechanism anything relies on. This asserts
      // only that giving up does not LATCH -- a record that failed every
      // attempt is left able to try, rather than marked done.
      var attempts = 0;
      final sink = await sinkWith(() => spokenWord('hola'));
      final r = CallRecord(
        roomId: '!r:server',
        transcripts: sink,
        sendEvent: (content, txid) async => '\$call',
        analytics: (id, uses, lang) async {},
        publishTranscript:
            ({
              required String callKey,
              required List<TranscriptSegment> segments,
              required int chunksCaptured,
              required int chunksTranscribed,
              required int chunksLost,
              required int chunksSuppressed,
              required bool captureRefused,
              required bool drainComplete,
              String? langCode,
            }) async {
              attempts++;
              if (attempts <= 3) throw StateError('a transient network blip');
            },
      );

      await r.finish(duration: kDur, video: false, callKey: '\$anchor');
      expect(attempts, 3, reason: 'it retried within the one finish');

      await r.finish(duration: kDur, video: false, callKey: '\$anchor');
      expect(attempts, 4, reason: 'giving up did not latch');
    });

    test('a call with SILENCE in it is not reported incomplete', () async {
      // The most common shape of a real call: some chunks carry speech, some
      // are quiet. Silence is not loss -- the provider processed the audio and
      // found nothing said -- but inferring "speech dropped" from
      // transcribed < captured marked almost every real transcript
      // incomplete, which empties the flag of meaning.
      var call = 0;
      final sink = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        transcribe: (_) async => (call++).isEven ? spokenWord('hola') : silent,
      );
      await sink.deliver(chunk(0));
      await sink.deliver(chunk(1));
      await sink.close();

      final r = record(sink, withPublisher: true);
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');

      expect(published.single.captured, 2);
      expect(published.single.transcribed, 1);
      expect(published.single.lost, 0, reason: 'silence is not loss');
    });

    test(
      'a chunk that FAILED and was never retried is reported lost',
      () async {
        final sink = CallTranscriptSink(
          userL1: 'en',
          userL2: 'es',
          transcribe: (_) async => throw StateError('the provider refused'),
        );
        await sink.deliver(chunk(0)).catchError((_) {});
        await sink.close();

        final r = record(sink, withPublisher: true);
        await r.finish(duration: kDur, video: false, callKey: '\$anchor');

        expect(published.single.lost, 1);
      },
    );

    test('hands over the accounting the reader depends on', () async {
      // Asserting only "the publisher was called" would not notice these being
      // swapped, dropped, or hard-coded -- and they are what a reader uses to
      // decide whether a half is complete.
      final sink = await sinkWith(() => spokenWord('hola'), chunks: 3);
      final r = record(sink, withPublisher: true);
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');

      expect(published.single.captured, 3);
      expect(published.single.transcribed, 3);
      expect(published.single.drained, isTrue);
      expect(published.single.segments, greaterThan(0));
    });

    test('publishes nothing without an anchor', () async {
      // A half nobody can query back is worse than none.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
      );
      await r.finish(duration: kDur, video: false);

      expect(published, isEmpty);
    });

    test('a call nobody answered still publishes its half', () async {
      // The publish happens before the answered check: a speaker who captured
      // nothing writes an empty half, and that is a different answer from no
      // half at all.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
      );
      await r.finish(
        duration: Duration.zero,
        video: false,
        answered: false,
        callKey: '\$anchor',
      );

      expect(published, hasLength(1));
    });

    test('nothing is published when no publisher is wired', () async {
      final r = record(await sinkWith(() => spokenWord('hola')));
      await r.finish(duration: kDur, video: false, callKey: '\$anchor');

      expect(published, isEmpty);
      expect(recorded, hasLength(1));
    });
  });

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

  test('a credit that failed is not applied a second time', () async {
    // Crediting is not safe to repeat. The analytics service writes the uses
    // locally as its first act and only then does the work that can fail, so a
    // second attempt does not retry the credit — it adds it again, and the
    // learner is recorded as having said everything twice. Their construct
    // counts, and the proficiency drawn from them, would be quietly wrong.
    //
    // What a retry would recover is only the part that already succeeded
    // locally; sending it on to the analytics room is the analytics service's
    // own job, on its own schedule, and it retries that itself.
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
        recorded.add((eventId: id, uses: uses.length, lang: lang));
        throw StateError('analytics unavailable after applying the uses');
      },
    );

    // Once for the internal retry, and again because the ordinary lifecycle
    // calls this twice.
    await r.finish(duration: const Duration(seconds: 10), video: false);
    await r.finish(duration: const Duration(seconds: 10), video: false);

    expect(creditAttempts, 1, reason: 'the learner is credited once, or never');
    expect(
      written,
      hasLength(1),
      reason: 'and the second call reused the call already in the timeline',
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
  group('a call event written by somebody else', () {
    test('renders when its duration is not a number', () {
      // Other clients and older versions of this one write this event too. A
      // cast that throws here takes down the whole timeline row rather than one
      // number in it.
      expect(
        CallRecord.durationOf({'duration_ms': '90000'}),
        const Duration(seconds: 90),
      );
      // Null rather than zero: not knowing how long a call lasted and knowing
      // it lasted no time are different facts, and the card and the chat list
      // disagreed about which they were showing.
      expect(CallRecord.durationOf({'duration_ms': 'soon'}), isNull);
      expect(CallRecord.durationOf(const {}), isNull);
      expect(
        CallRecord.durationOf({'duration_ms': 1500}),
        const Duration(milliseconds: 1500),
      );
    });
  });
  group('a call that rang out', () {
    test('is written with no talking time at all', () {
      // Observed on a live homeserver: a call nobody answered was written with
      // answered:false AND fifteen seconds of duration. Both come from the same
      // fact — whether anybody was ever on the other end — so they cannot
      // honestly disagree, and a learner's history should not show time spent
      // talking to nobody.
      final content = <String, Object?>{};
      final r = CallRecord(
        roomId: '!r:server',
        transcripts: CallTranscriptSink(
          userL1: 'en',
          userL2: 'es',
          transcribe: (_) async => SpeechToTextResponseModel(results: const []),
        ),
        sendEvent: (c, txid) async {
          content.addAll(c);
          return '\$call';
        },
        analytics: (id, uses, lang) async {},
      );

      return r
          .finish(duration: Duration.zero, video: false, answered: false)
          .then((_) {
            expect(content['answered'], isFalse);
            expect(content['duration_ms'], 0);
            expect(content['body'], 'Missed call');
          });
    });
  });
  group('the survivor card', () {
    test(
      'a non-writer that already credited analytics can still write it',
      () async {
        // The old single _eventId slot made "analytics anchored" read as "the
        // card exists", which blocked the survivor before it started.
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.finish(
          duration: const Duration(seconds: 30),
          video: false,
          writeTimelineEvent: false,
          anchorEventId: r'$ring',
        );
        expect(
          recorded,
          hasLength(1),
          reason: 'analytics credited to the ring',
        );
        expect(written, isEmpty, reason: 'the non-writer posted no card');

        await r.writeSurvivorCard(
          duration: const Duration(seconds: 30),
          video: false,
          callKey: r'$caller-membership',
          answered: true,
          declined: false,
          callerId: '@caller:server',
        );

        expect(written, hasLength(1));
        expect(written.single[CallRecord.callKeyField], r'$caller-membership');
        expect(written.single['answered'], isTrue);
        expect(written.single['declined'], isFalse);
        expect(written.single['caller'], '@caller:server');
      },
    );

    test(
      'the survivor writes the outcome it is given, never an assumption',
      () async {
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.writeSurvivorCard(
          duration: Duration.zero,
          video: false,
          callKey: r'$nobody-came',
          answered: false,
          declined: false,
          callerId: '@caller:server',
        );
        expect(written.single['answered'], isFalse);
        expect(written.single['declined'], isFalse);
      },
    );

    test(
      'a device that already wrote its card never survivor-writes',
      () async {
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.writeCard(
          duration: const Duration(seconds: 30),
          video: false,
          answered: true,
          declined: false,
          writeTimelineEvent: true,
          callKey: r'$key',
        );
        expect(written, hasLength(1));

        await r.writeSurvivorCard(
          duration: const Duration(seconds: 30),
          video: false,
          callKey: r'$key',
          answered: true,
          declined: false,
        );
        expect(written, hasLength(1), reason: 'one card per device, ever');
      },
    );

    test('a credit that stored nothing can be tried again', () async {
      // Crediting is marked done BEFORE the write, because doing it twice
      // records the learner as having said everything twice. The one failure
      // that is safe to retry is the one that stored nothing at all, and
      // without putting the flag back the ordinary second call returned
      // immediately and that speech was gone.
      var attempts = 0;
      final r = CallRecord(
        roomId: '!r:server',
        transcripts: await sinkWith(() => spokenWord('hola')),
        sendEvent: (content, txid) async {
          written.add(content);
          return r'$card';
        },
        analytics: (eventId, uses, language) async {
          attempts++;
          throw const CallAnalyticsNotStored('the store was closed');
        },
      );

      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        writeTimelineEvent: true,
        anchorEventId: r'$ring',
      );
      final afterFirst = attempts;
      expect(afterFirst, greaterThan(0));

      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        writeTimelineEvent: true,
        anchorEventId: r'$ring',
      );
      expect(
        attempts,
        greaterThan(afterFirst),
        reason: 'a credit that stored nothing was never tried again',
      );
    });

    test('every writer stamps the same key field', () async {
      final r = record(await sinkWith(() => spokenWord('hola')));
      await r.writeCard(
        duration: const Duration(seconds: 5),
        video: false,
        answered: true,
        declined: false,
        writeTimelineEvent: true,
        callKey: r'$key',
        callerId: '@me:server',
      );
      expect(written.single[CallRecord.callKeyField], r'$key');

      final r2 = record(await sinkWith(() => spokenWord('hola')));
      await r2.finish(
        duration: const Duration(seconds: 5),
        video: false,
        callKey: r'$key2',
      );
      expect(written.last[CallRecord.callKeyField], r'$key2');
    });

    test(
      'a call whose identity was never learned is written keyless',
      () async {
        final r = record(await sinkWith(() => spokenWord('hola')));
        await r.writeCard(
          duration: const Duration(seconds: 5),
          video: false,
          answered: true,
          declined: false,
          writeTimelineEvent: true,
        );
        expect(written.single.containsKey(CallRecord.callKeyField), isFalse);
      },
    );

    test(
      'a transient publish failure is RETRIED, not merely permitted',
      () async {
        // The flag was reset on failure and the log said it could be retried --
        // and nothing ever retried. finish() runs once per call behind a latch
        // and the screen is gone afterwards, so the one attempt was the only
        // attempt. Permitting a retry is not performing one, and the speaker
        // read as ABSENT for the difference.
        final r = record(
          await sinkWith(() => spokenWord('hola')),
          withPublisher: true,
          publishFailures: 1,
        );

        await r.finish(
          duration: const Duration(seconds: 30),
          video: false,
          callKey: r'$anchor',
        );

        expect(
          publishAttempts.length,
          greaterThan(1),
          reason: 'it tried again',
        );
        expect(published, hasLength(1), reason: 'and the half actually landed');
      },
    );

    test('the retry resends the SAME half, read once up front', () async {
      // The deterministic transaction id only collapses a resend if the resend
      // IS the same event. Re-reading the sink per attempt sends different
      // content under one id, which the server does not collapse -- it keeps
      // the first and discards the rest.
      final seen = <String>[];
      final sink = _ShiftingSink();
      var attempts = 0;
      final r = CallRecord(
        roomId: '!r:server',
        transcripts: sink,
        sendEvent: (content, txid) async => r'$call',
        analytics: (id, uses, lang) async {},
        publishTranscript:
            ({
              required String callKey,
              required List<TranscriptSegment> segments,
              required int chunksCaptured,
              required int chunksTranscribed,
              required int chunksLost,
              required int chunksSuppressed,
              required bool captureRefused,
              required bool drainComplete,
              String? langCode,
            }) async {
              seen.add(segments.single.text);
              if (++attempts < 3) throw StateError('a transient blip');
            },
      );

      await r.finish(duration: kDur, video: false, callKey: r'$anchor');

      expect(seen, hasLength(3));
      expect(seen.toSet(), hasLength(1), reason: 'all three were identical');
    });

    test('the retry carries identical words through the real sink', () async {
      // The deterministic transaction id only collapses a resend if the resend
      // IS the same event. Re-reading the sink per attempt would send
      // different content under one id, which the server would not collapse.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
        publishFailures: 2,
      );

      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: r'$anchor',
      );

      expect(publishAttempts, hasLength(3));
      expect(
        publishAttempts.map((a) => a.join('|')).toSet(),
        hasLength(1),
        reason: 'every attempt carried identical words',
      );
    });

    test('a half that never lands does not block the call credit', () async {
      // Publishing runs ahead of the credit guard deliberately. Its retries
      // must not be able to swallow the hangup path with them.
      final r = record(
        await sinkWith(() => spokenWord('hola')),
        withPublisher: true,
        publishError: Exception('down'),
      );

      await r.finish(
        duration: const Duration(seconds: 30),
        video: false,
        callKey: r'$anchor',
      );

      expect(published, isEmpty);
      expect(written, hasLength(1), reason: 'the card was still written');
    });
  });

  group('durationOf, reading somebody else\'s number', () {
    test('a duration that cannot be one reads as unknown', () {
      // num.tryParse accepts "NaN" and "Infinity", and .round() on either
      // throws -- so a card carrying one of those words took the whole row
      // down rather than reading as a call of unknown length.
      // Null, not zero: a card stating no usable length and a call that
      // really lasted none are different facts, and collapsing them made the
      // card print "0:00" while the chat list printed nothing.
      for (final word in ['NaN', 'Infinity', '-Infinity', '-61000']) {
        expect(
          CallRecord.durationOf({'duration_ms': word}),
          isNull,
          reason: word,
        );
      }
      expect(CallRecord.durationOf(const {}), isNull, reason: 'absent');
      expect(
        CallRecord.durationOf(const {'duration_ms': 0}),
        Duration.zero,
        reason: 'a real zero is still a stated zero',
      );
    });

    test('an ordinary duration still reads', () {
      expect(
        CallRecord.durationOf({'duration_ms': 1500}),
        const Duration(milliseconds: 1500),
      );
      expect(
        CallRecord.durationOf({'duration_ms': '1500'}),
        const Duration(milliseconds: 1500),
      );
    });
  });
}

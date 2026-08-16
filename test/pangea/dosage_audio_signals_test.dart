import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_coverage.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_audio_signals.dart';
import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
import 'package:fluffychat/features/dosage/dosage_shared_player_tracker.dart';

/// The three listening categories, the emitter, and the shared-player tracker.
///
/// The failure this suite exists to catch is **a category attributed to the
/// wrong caller**. The app plays every sound through ONE global player, and
/// several surfaces are subscribed to it at once, so the timeline bubble sees
/// the toolbar's paid read-aloud and the toolbar sees the bubble's voice
/// message. Nothing in the player state says which is which; only the owner id
/// does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mxid = '@learner:example.org';
  const token = 'syt_student_token';
  const roomId = '!room:example.org';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_audio');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    DosageAudioBuffer.debugResetAccounts();
  });

  tearDown(DosageAudioBuffer.debugResetAccounts);

  group('category naming', () {
    test('every listening category has a distinct, stable wire name', () {
      expect(DosageListeningCategory.values.map((c) => c.wireName), [
        'peer',
        'auto_read',
        'tap_read',
      ]);
    });

    test('coverage has FOUR categories — voiceSend is not a listening one', () {
      // Speaking's magnitude is derived server-side, so there is no speaking
      // playback event; but the server only learns a voice message exists from a
      // client row, so its DENOMINATOR still needs a declaration (D-V2-15).
      expect(DosageCoverageCategory.values.map((c) => c.wireName), [
        'peer',
        'auto_read',
        'tap_read',
        'voice_send',
      ]);
      // The type system, not a convention, is what stops a listening event being
      // tagged voice_send: DosageAudioEvent takes a DosageListeningCategory,
      // which has no such member.
      expect(
        DosageListeningCategory.values.map((c) => c.name),
        isNot(contains('voiceSend')),
      );
    });

    test('each listening category maps to its own coverage category', () {
      for (final category in DosageListeningCategory.values) {
        expect(category.coverage.wireName, category.wireName);
      }
    });
  });

  group('timeline category (the one runtime discriminator in the feature)', () {
    test('audio somebody ELSE sent is peer listening', () {
      expect(
        DosageListeningCategory.forTimelineAudio(
          senderId: '@classmate:example.org',
          ownUserId: mxid,
        ),
        DosageListeningCategory.peer,
      );
    });

    test('the BOT counts as somebody else', () {
      // v1 wrote bot audio out of scope on the premise that the bot never sends
      // m.audio. It does — measured on staging, most recently 2026-08-03 — and a
      // bot-mediated course is where most received audio actually lives.
      expect(
        DosageListeningCategory.forTimelineAudio(
          senderId: '@pangeabot:example.org',
          ownUserId: mxid,
        ),
        DosageListeningCategory.peer,
      );
    });

    test('replaying YOUR OWN voice message is not listening', () {
      expect(
        DosageListeningCategory.forTimelineAudio(
          senderId: mxid,
          ownUserId: mxid,
        ),
        isNull,
      );
    });

    test('an unresolved account attributes nothing rather than guessing', () {
      for (final own in [null, '']) {
        expect(
          DosageListeningCategory.forTimelineAudio(
            senderId: '@classmate:example.org',
            ownUserId: own,
          ),
          isNull,
        );
      }
    });
  });

  group('the event carries no source identity', () {
    test('exactly five keys, and none of them names the source', () {
      final json = DosageAudioEvent.fromPlayback(
        playbackId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        roomId: roomId,
        category: DosageListeningCategory.peer,
        elapsed: const Duration(seconds: 7),
        endedAt: DateTime.utc(2026, 1, 1, 12),
      ).toJson();

      expect(json.keys.toSet(), {
        'playback_id',
        'room_id',
        'category',
        'elapsed_ms',
        'ts',
      });
      // The call site HAS the source event id and the source sender in hand at
      // this moment. Both are dropped here, at the point of collection, because
      // carrying them would build a per-student record of which peers a learner
      // attends to — a social-graph fact about a third party that no counter
      // consumes.
      expect(json.keys, isNot(contains('event_id')));
      expect(json.keys, isNot(contains('sender')));
      expect(json.keys, isNot(contains('sender_mxid')));
      expect(json.keys, isNot(contains('msg_id')));
      expect(json['elapsed_ms'], 7000);
      expect(json['category'], 'peer');
      expect(json['ts'], '2026-01-01T12:00:00.000Z');
    });

    test('an absurd magnitude is clamped rather than sent as-is', () {
      final event = DosageAudioEvent.fromPlayback(
        playbackId: 'id',
        roomId: roomId,
        category: DosageListeningCategory.tapRead,
        elapsed: const Duration(days: 2),
        endedAt: DateTime.utc(2026, 1, 1),
      );
      expect(event.elapsedMs, DosageAudioEvent.maxElapsedMs);
    });
  });

  group('coverage declaration', () {
    test('carries a period and its category, and nothing else', () {
      final json = DosageAudioCoverage(
        coverageId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        category: DosageCoverageCategory.voiceSend,
        periodStart: DateTime.utc(2026, 1, 1, 12),
        periodEnd: DateTime.utc(2026, 1, 1, 12, 5),
      ).toJson();
      expect(json.keys.toSet(), {
        'coverage_id',
        'category',
        'period_start',
        'period_end',
      });
      expect(json['category'], 'voice_send');
    });

    test('a zero-length or inverted period claims nothing', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      expect(
        DosageAudioCoverage(
          coverageId: 'id',
          category: DosageCoverageCategory.peer,
          periodStart: at,
          periodEnd: at,
        ).isValid,
        isFalse,
      );
      expect(
        DosageAudioCoverage(
          coverageId: 'id',
          category: DosageCoverageCategory.peer,
          periodStart: at,
          periodEnd: at.subtract(const Duration(minutes: 1)),
        ).isValid,
        isFalse,
      );
    });
  });

  group('emitter', () {
    test('records a playback against the account buffer', () {
      final buffer = DosageAudioBuffer();
      DosageAudioBuffer.debugPutAccount(mxid, buffer);

      DosageAudioSignals.recordPlayback(
        category: DosageListeningCategory.autoRead,
        roomId: roomId,
        elapsed: const Duration(seconds: 3),
        userId: mxid,
        accessToken: token,
      );

      expect(buffer.bufferedEvents, hasLength(1));
      expect(
        buffer.bufferedEvents.single.category,
        DosageListeningCategory.autoRead,
      );
      expect(buffer.bufferedEvents.single.elapsedMs, 3000);
    });

    test('each playback gets its own idempotency key', () {
      final buffer = DosageAudioBuffer();
      DosageAudioBuffer.debugPutAccount(mxid, buffer);
      for (var i = 0; i < 5; i++) {
        DosageAudioSignals.recordPlayback(
          category: DosageListeningCategory.peer,
          roomId: roomId,
          elapsed: const Duration(seconds: 1),
          userId: mxid,
          accessToken: token,
        );
      }
      final ids = buffer.bufferedEvents.map((e) => e.playbackId).toSet();
      expect(
        ids,
        hasLength(5),
        reason: 'a shared key would make the server dedupe real playbacks away',
      );
    });

    test('drops a playback it cannot attribute or bucket', () {
      final buffer = DosageAudioBuffer();
      DosageAudioBuffer.debugPutAccount(mxid, buffer);

      // No room => no course bucket, so the signal is structurally unusable.
      DosageAudioSignals.recordPlayback(
        category: DosageListeningCategory.peer,
        roomId: '',
        elapsed: const Duration(seconds: 3),
        userId: mxid,
        accessToken: token,
      );
      // Nothing measured.
      DosageAudioSignals.recordPlayback(
        category: DosageListeningCategory.peer,
        roomId: roomId,
        elapsed: Duration.zero,
        userId: mxid,
        accessToken: token,
      );
      // Unknown account: attributing it to the wrong learner is worse than
      // losing it, and coverage makes the loss a withheld period.
      DosageAudioSignals.recordPlayback(
        category: DosageListeningCategory.peer,
        roomId: roomId,
        elapsed: const Duration(seconds: 3),
        userId: null,
        accessToken: token,
      );

      expect(buffer.bufferedEvents, isEmpty);
    });

    test('never throws, whatever it is handed', () {
      expect(
        () => DosageAudioSignals.recordPlayback(
          category: DosageListeningCategory.peer,
          roomId: roomId,
          elapsed: const Duration(seconds: 3),
          userId: mxid,
          accessToken: null,
        ),
        returnsNormally,
      );
    });
  });

  group('voice-send coverage is backed by a delivered envelope', () {
    test('a lost envelope withholds voice_send for that period', () async {
      final buffer = DosageAudioBuffer(now: DateTime.now);
      DosageAudioBuffer.debugPutAccount(mxid, buffer);
      buffer.start();

      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: mxid,
        deviceId: 'DEVICE-A',
        accessToken: token,
        msgEventId: r'$voice:example.org',
        body: 'hola',
        // The route is not deployed yet — the normal case for now.
        client: MockClient((_) async => http.Response('', 404)),
        onEnvelopeSettled: DosageAudioSignals.voiceSendReporter(userId: mxid),
      );
      await pumpEventQueue();

      expect(
        buffer.voiceSendCoveredForTest,
        isFalse,
        reason:
            'the server never learned the message exists, so it must not be '
            'licensed to serve a speaking zero for this period',
      );
    });

    test('a delivered envelope leaves voice_send declarable', () async {
      final buffer = DosageAudioBuffer(now: DateTime.now);
      DosageAudioBuffer.debugPutAccount(mxid, buffer);
      buffer.start();

      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: mxid,
        deviceId: 'DEVICE-A',
        accessToken: token,
        msgEventId: r'$voice:example.org',
        body: 'hola',
        client: MockClient((_) async => http.Response('', 202)),
        onEnvelopeSettled: DosageAudioSignals.voiceSendReporter(userId: mxid),
      );
      await pumpEventQueue();

      expect(buffer.voiceSendCoveredForTest, isTrue);
    });

    test('an unresolved send leaves nothing outstanding', () async {
      // The send never landed, so there is no message the server could be
      // missing — this must not withhold speaking for the period.
      final buffer = DosageAudioBuffer(now: DateTime.now);
      DosageAudioBuffer.debugPutAccount(mxid, buffer);
      buffer.start();

      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: mxid,
        deviceId: 'DEVICE-A',
        accessToken: token,
        msgEventId: null,
        body: 'hola',
        client: MockClient((_) async => http.Response('', 202)),
        onEnvelopeSettled: DosageAudioSignals.voiceSendReporter(userId: mxid),
      );
      await pumpEventQueue();

      expect(
        buffer.voiceSendCoveredForTest,
        isTrue,
        reason: 'a guard exit must settle, or the counter is dark forever',
      );
    });

    test('text sends are untouched: no delivery inspection, no coverage', () {
      // The shared emitter must behave exactly as before for every other
      // caller — the settle path is opt-in.
      final buffer = DosageAudioBuffer(now: DateTime.now);
      DosageAudioBuffer.debugPutAccount(mxid, buffer);
      buffer.start();

      DosageMessageSignals.emitForSentMessage(
        roomId: roomId,
        userId: mxid,
        deviceId: 'DEVICE-A',
        accessToken: token,
        msgEventId: r'$text:example.org',
        body: 'hola',
        client: MockClient((_) async => http.Response('', 404)),
      );

      expect(buffer.voiceSendCoveredForTest, isTrue);
    });
  });

  group('shared-player attribution', () {
    late DosageAudioBuffer buffer;
    late DateTime clock;

    DosageSharedPlayerTracker tracker({
      required DosageListeningCategory category,
      required String ownerId,
    }) => DosageSharedPlayerTracker(
      category: category,
      roomId: roomId,
      ownerId: ownerId,
      userId: () => mxid,
      accessToken: () => token,
      now: () => clock,
      buffer: buffer,
    );

    setUp(() {
      buffer = DosageAudioBuffer();
      clock = DateTime.utc(2026, 1, 1, 12);
    });

    void advance(Duration d) => clock = clock.add(d);

    test('a completed playback emits its category once', () {
      final t = tracker(
        category: DosageListeningCategory.peer,
        ownerId: r'$msg:example.org',
      );
      t.update(
        playing: true,
        completed: false,
        currentOwnerId: r'$msg:example.org',
      );
      advance(const Duration(seconds: 9));
      t.update(
        playing: false,
        completed: true,
        currentOwnerId: r'$msg:example.org',
      );

      expect(buffer.bufferedEvents, hasLength(1));
      expect(
        buffer.bufferedEvents.single.category,
        DosageListeningCategory.peer,
      );
      expect(buffer.bufferedEvents.single.elapsedMs, 9000);
    });

    test(
      'the toolbar taking the shared player is NOT counted as peer listening',
      () {
        // THE wrong-category failure. Every mounted timeline bubble is
        // subscribed to the one global player, and the toolbar's speaker button
        // plays paid read-aloud through that same player under its own id. A
        // bubble that measured "the player is playing" would bank category 3
        // audio as category 1.
        final bubble = tracker(
          category: DosageListeningCategory.peer,
          ownerId: r'$msg:example.org',
        );

        // The toolbar owns the player now.
        const toolbarOwner = r'$msg:example.org_button';
        bubble.update(
          playing: true,
          completed: false,
          currentOwnerId: toolbarOwner,
        );
        advance(const Duration(seconds: 30));
        bubble.update(
          playing: false,
          completed: true,
          currentOwnerId: toolbarOwner,
        );

        expect(
          buffer.bufferedEvents,
          isEmpty,
          reason: 'the bubble measured a playback that was never its own',
        );
      },
    );

    test('losing the player mid-playback keeps what was heard, and stops', () {
      final bubble = tracker(
        category: DosageListeningCategory.peer,
        ownerId: r'$msg:example.org',
      );
      bubble.update(
        playing: true,
        completed: false,
        currentOwnerId: r'$msg:example.org',
      );
      advance(const Duration(seconds: 4));

      // The learner opens the toolbar and taps the speaker: the toolbar takes
      // the player mid-message.
      bubble.update(
        playing: true,
        completed: false,
        currentOwnerId: r'$msg:example.org_button',
      );
      advance(const Duration(seconds: 20));
      bubble.update(
        playing: false,
        completed: true,
        currentOwnerId: r'$msg:example.org_button',
      );

      expect(buffer.bufferedEvents, hasLength(1));
      expect(
        buffer.bufferedEvents.single.elapsedMs,
        4000,
        reason: 'the 4 s heard is real; the 20 s after belongs to the toolbar',
      );
    });

    test(
      'the in-bubble and overlay instances of one message cannot double-count',
      () {
        // message_content builds TWO AudioPlayerWidgets per audio message and
        // suffixes the overlay one's id. Only the overlay can play today, but
        // the emitter must not depend on that staying true.
        final inBubble = tracker(
          category: DosageListeningCategory.peer,
          ownerId: r'$msg:example.org',
        );
        final overlay = tracker(
          category: DosageListeningCategory.peer,
          ownerId: r'$msg:example.org_overlay',
        );

        const owner = r'$msg:example.org_overlay';
        for (final t in [inBubble, overlay]) {
          t.update(playing: true, completed: false, currentOwnerId: owner);
        }
        advance(const Duration(seconds: 5));
        for (final t in [inBubble, overlay]) {
          t.update(playing: false, completed: true, currentOwnerId: owner);
        }

        expect(
          buffer.bufferedEvents,
          hasLength(1),
          reason: 'one playback, one signal, however many widgets watched it',
        );
        expect(buffer.bufferedEvents.single.elapsedMs, 5000);
      },
    );

    test('completion then close emits ONCE, not twice', () {
      // Completion closes the measurement; the surface's dispose closes it
      // again moments later.
      final t = tracker(
        category: DosageListeningCategory.tapRead,
        ownerId: 'owner',
      );
      t.update(playing: true, completed: false, currentOwnerId: 'owner');
      advance(const Duration(seconds: 2));
      t.update(playing: false, completed: true, currentOwnerId: 'owner');
      t.close();

      expect(buffer.bufferedEvents, hasLength(1));
    });

    test(
      'losing the player with NO further state event cannot inflate the total',
      () {
        // The surface that takes the player disposes the one we are subscribed
        // to, so the closing transition may never be delivered. Ownership is the
        // reliable signal, and closing on it is what stops the meter running on
        // through somebody else's playback until this surface is disposed.
        final t = tracker(
          category: DosageListeningCategory.tapRead,
          ownerId: 'toolbar',
        );
        t.update(playing: true, completed: false, currentOwnerId: 'toolbar');
        advance(const Duration(seconds: 3));

        // Ownership moves; the surface closes on the notifier rather than
        // waiting for a state event that is not coming.
        t.close();
        advance(const Duration(minutes: 4));
        t.close();

        expect(buffer.bufferedEvents, hasLength(1));
        expect(
          buffer.bufferedEvents.single.elapsedMs,
          3000,
          reason: 'the 4 minutes after the handover belong to another surface',
        );
      },
    );

    test('closing without playback emits nothing', () {
      final t = tracker(
        category: DosageListeningCategory.tapRead,
        ownerId: 'owner',
      );
      t.close();
      expect(buffer.bufferedEvents, isEmpty);
    });

    test('a playback abandoned by navigating away is still counted', () {
      // No playback path distinguishes "finished" from "stopped", and the
      // learner heard what they heard.
      final t = tracker(
        category: DosageListeningCategory.tapRead,
        ownerId: 'owner',
      );
      t.update(playing: true, completed: false, currentOwnerId: 'owner');
      advance(const Duration(seconds: 6));
      t.close();

      expect(buffer.bufferedEvents.single.elapsedMs, 6000);
    });
  });
}

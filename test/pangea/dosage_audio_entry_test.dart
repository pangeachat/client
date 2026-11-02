import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_entry.dart';
import 'package:fluffychat/features/dosage/dosage_audio_signals.dart';
import 'package:fluffychat/features/dosage/dosage_call_time.dart';

/// Audio time as a row in the analytics room: the shape, what readers do with
/// it, and what each signal writes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mxid = '@learner:example.org';
  final ts = DateTime.utc(2026, 11, 2, 12, 34, 56, 789);

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_entry');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    // Dark on purpose: the room write must not depend on the POST lane's flags.
    dotenv.testLoad();
    DosageAudioBuffer.debugResetAccounts();
    ListeningExposureBuffer.debugResetAccounts();
  });

  tearDown(() {
    DosageAudioBuffer.debugResetAccounts();
    ListeningExposureBuffer.debugResetAccounts();
  });

  List<OneConstructUse> held() =>
      ListeningExposureBuffer.forAccount(mxid)!.drainAudioEntries();

  group('the row', () {
    OneConstructUse entry() => DosageAudioEntry.use(
      id: 'playback-1',
      category: DosageAudioEntry.callCategory,
      durMs: 1800000,
      ts: ts,
    )!;

    test('carries the duration, the id and no room or message', () {
      expect(entry().toJson(), {
        'useType': 'aud',
        'chatId': null,
        'timeStamp': '2026-11-02T12:34:56.789Z',
        'form': null,
        'msgId': null,
        'lemma': '',
        'constructType': 'g',
        'categories': 'call_connected',
        'id': 'playback-1',
        'xp': 0,
        'durMs': 1800000,
      });
    });

    test('survives the local store, whose batches are JSON', () {
      final json = jsonDecode(jsonEncode(entry().toJson()));
      final back = OneConstructUse.fromJson(Map<String, dynamic>.from(json));

      expect(back.useType, ConstructUseTypeEnum.aud);
      expect(back.durMs, 1800000);
      expect(back.toJson(), entry().toJson());
    });

    test('every app skips it when reading the room, before parsing it', () {
      final model = ConstructAnalyticsModel.fromJson({
        'uses': [entry().toJson()],
      });

      expect(model.uses, isEmpty);
    });

    test('a row still waiting to upload is hidden from local reads', () {
      expect(entry().identifier.isInvalid, isTrue);
      expect(entry().xp, 0);
      expect(ConstructUseTypeEnum.aud.pointValue, 0);
      expect(ConstructUseTypeEnum.aud.sentByUser, isFalse);
      expect(ConstructUseTypeEnum.aud.summaryEnumType, isNull);
    });

    test('every other use serializes exactly as before', () {
      final use = OneConstructUse(
        useType: ConstructUseTypeEnum.wa,
        lemma: 'uno',
        constructType: ConstructTypeEnum.vocab,
        metadata: ConstructUseMetaData(roomId: '!r', timeStamp: ts),
        category: 'noun',
        form: 'uno',
        xp: 3,
      );

      expect(use.toJson().containsKey('durMs'), isFalse);
      expect(use.toJson()['constructType'], 'vocab');
    });

    test('nothing with no real duration becomes a row', () {
      for (final ms in [0, -1, DosageAudioEntry.maxDurMs + 1]) {
        expect(
          DosageAudioEntry.use(
            id: 'x',
            category: DosageAudioEntry.voiceCategory,
            durMs: ms,
            ts: ts,
          ),
          isNull,
        );
      }
      expect(
        DosageAudioEntry.use(
          id: '',
          category: DosageAudioEntry.voiceCategory,
          durMs: 1000,
          ts: ts,
        ),
        isNull,
      );
    });

    test('stays under the 270 bytes measured for similar rows', () {
      final call = DosageAudioEntry.use(
        id: 'call:${'a' * 64}',
        category: DosageAudioEntry.callCategory,
        durMs: 1800000,
        ts: ts,
      )!;
      final voice = DosageAudioEntry.use(
        id: '\$${'a' * 43}',
        category: DosageAudioEntry.voiceCategory,
        durMs: 12000,
        ts: ts,
      )!;
      final play = DosageAudioEntry.use(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        category: DosageListeningCategory.toolbarRead.wireName,
        durMs: 4200,
        ts: ts,
      )!;

      int bytes(OneConstructUse use) =>
          utf8.encode(jsonEncode(use.toJson())).length;

      // ignore: avoid_print
      print(
        'audio entry bytes: call=${bytes(call)} voice=${bytes(voice)} '
        'play=${bytes(play)}',
      );
      expect(bytes(call), lessThan(270));
      expect(bytes(voice), lessThan(270));
      expect(bytes(play), lessThan(270));
    });
  });

  group('each signal writes one row', () {
    test('a playback, under its POST id', () {
      final buffer = DosageAudioBuffer();
      DosageAudioSignals.recordPlayback(
        category: DosageListeningCategory.peer,
        roomId: '!room:example.org',
        elapsed: const Duration(seconds: 7),
        userId: mxid,
        accessToken: 'token',
        endedAt: ts,
        buffer: buffer,
      );

      final rows = held();
      expect(rows, hasLength(1));
      expect(rows.single.useType, ConstructUseTypeEnum.aud);
      expect(rows.single.category, 'peer');
      expect(rows.single.durMs, 7000);
      expect(rows.single.id, isNotEmpty);
      expect(rows.single.metadata.roomId, isNull);
      expect(rows.single.timeStamp, ts);
    });

    test('a voice message, under its event id', () {
      DosageAudioSignals.recordVoiceMessage(
        msgId: r'$voice',
        roomId: '!room:example.org',
        durationMs: 12000,
        userId: mxid,
        accessToken: 'token',
        sentAt: ts,
      );

      final row = held().single;
      expect(row.id, r'$voice');
      expect(row.category, DosageAudioEntry.voiceCategory);
      expect(row.durMs, 12000);
    });

    test('a call, under the server\'s key for it, labelled connected time', () {
      final started = DateTime.utc(2026, 11, 2, 12);
      DosageAudioSignals.recordCall(
        roomId: '!dm:example.org',
        callKey: 'call-key',
        deviceId: 'DEVICE',
        talkStartedAt: started,
        connected: const Duration(minutes: 30),
        userId: mxid,
        accessToken: 'token',
        endedAt: ts,
      );

      final row = held().single;
      final callId = DosageCallTime.idFor(
        roomId: '!dm:example.org',
        callKey: 'call-key',
        deviceId: 'DEVICE',
        talkStartedAt: started,
      );
      expect(row.id, 'call:$callId');
      expect(row.category, 'call_connected');
      expect(row.durMs, 1800000);
    });

    test('a call retried for one stay is one id', () {
      for (var i = 0; i < 2; i++) {
        DosageAudioSignals.recordCall(
          roomId: '!dm:example.org',
          callKey: 'call-key',
          deviceId: 'DEVICE',
          talkStartedAt: ts,
          connected: const Duration(minutes: 1),
          userId: mxid,
          accessToken: 'token',
        );
      }

      expect(held().map((row) => row.id).toSet(), hasLength(1));
    });

    test('an unknown account writes nothing', () {
      DosageAudioSignals.recordVoiceMessage(
        msgId: r'$voice',
        roomId: '!room:example.org',
        durationMs: 12000,
        userId: null,
        accessToken: 'token',
      );

      expect(held(), isEmpty);
    });
  });

  group('the held rows', () {
    OneConstructUse entry(String id) => DosageAudioEntry.use(
      id: id,
      category: DosageAudioEntry.voiceCategory,
      durMs: 1000,
      ts: ts,
    )!;

    test('are drained once, and a failed write puts them back first', () {
      final buffer = ListeningExposureBuffer();
      buffer.recordAudioEntry(entry('a'));
      final drained = buffer.drainAudioEntries();
      buffer.recordAudioEntry(entry('b'));

      expect(drained.map((row) => row.id), ['a']);

      buffer.restoreAudioEntries(drained);

      expect(buffer.drainAudioEntries().map((row) => row.id), ['a', 'b']);
      expect(buffer.drainAudioEntries(), isEmpty);
    });

    test('tell the service at once, not at the next heartbeat', () {
      final buffer = ListeningExposureBuffer();
      var told = 0;
      buffer.onAudioEntry = () => told++;

      buffer.recordAudioEntry(entry('a'));

      expect(told, 1);
    });

    test('are bounded, dropping the oldest', () {
      final buffer = ListeningExposureBuffer();
      for (var i = 0; i < ListeningExposureBuffer.maxHeldRows + 1; i++) {
        buffer.recordAudioEntry(entry('$i'));
      }

      final rows = buffer.drainAudioEntries();
      expect(rows, hasLength(ListeningExposureBuffer.maxHeldRows));
      expect(rows.first.id, '1');
    });

    test('are not exposure, and do not move the exposure count', () {
      final buffer = ListeningExposureBuffer();
      buffer.recordAudioEntry(entry('a'));

      expect(buffer.pendingExposures, 0);
      expect(buffer.drain('es'), isEmpty);
    });
  });
}

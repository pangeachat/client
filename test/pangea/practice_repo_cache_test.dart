import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/analytics/construct_form.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_generation_repo.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// [PracticeRepo]'s exercise cache moved onto [ExpiringStorageBox] so the
/// per-read expiry sweep stops touching every cached exercise (#8393 audit
/// follow-up). What's pinned here is the contract that must not move: the
/// on-disk entry shape (`{practiceActivity, timestamp}`), so entries written
/// by the previous build are still read; a parseable fresh entry is a hit
/// served from the box alone (no MatrixState, no network); an entry older
/// than the 1-minute TTL is a miss and is dropped; a stale or unparseable
/// neighbour never affects a hit; and `invalidate` drops the entry.
///
/// Payloads are planted server-shaped (with `tgt_constructs`) because
/// `PracticeExerciseModel.fromJson` requires that key while `toJson` never
/// emits it — so what the repo itself writes cannot currently be read back.
/// That's a pre-existing gap outside this refactor's scope — see #8432.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const box = 'practice_activity_cache';
  late GetStorage raw;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('practice_repo_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init(box);
  });

  setUp(() async {
    raw = GetStorage(box);
    await raw.erase();
  });

  PangeaToken token(String content) => PangeaToken(
    text: PangeaTokenText.fromJson({'content': content, 'offset': 0}),
    lemma: Lemma(text: content, saveVocab: true, form: content),
    pos: 'NOUN',
    morph: const {},
  );

  final tokens = [token('gato'), token('perro')];

  MessagePracticeExerciseRequest request() => MessagePracticeExerciseRequest(
    userL1: 'en',
    userL2: 'es',
    exerciseQualityFeedback: null,
    target: PracticeTarget(
      tokens: tokens,
      exerciseType: PracticeExerciseTypeEnum.wordMeaning,
    ),
  );

  PracticeExerciseModel exercise() => LemmaMeaningPracticeExerciseModel(
    langCode: 'es',
    tokens: tokens,
    matchContent: MatchPracticeExercise(
      matchInfo: {
        for (final t in tokens)
          ConstructForm(
            form: t.text.content,
            cId: ConstructIdentifier(
              lemma: t.lemma.text,
              type: ConstructTypeEnum.vocab,
              category: 'NOUN',
            ),
          ): [
            '${t.text.content}-meaning',
          ],
      },
    ),
  );

  /// The exercise as the choreographer would send it (see file comment).
  Map<String, dynamic> serverShaped() => {
    ...exercise().toJson(),
    'tgt_constructs': <dynamic>[],
  };

  /// Plants an entry in the on-disk shape the pre-refactor code used.
  Future<void> plantLegacyEntry(
    MessagePracticeExerciseRequest req,
    DateTime at, {
    Map<String, dynamic>? payload,
  }) => raw.write(req.hashCode.toString(), {
    'practiceActivity': payload ?? serverShaped(),
    'timestamp': at.toIso8601String(),
  });

  test('a fresh legacy-shaped entry is a hit served from the box', () async {
    final req = request();
    await plantLegacyEntry(req, DateTime.now());

    // MatrixState is not initialized in this test, so anything but a pure
    // cache hit would fall through to an error result.
    final result = await PracticeRepo.getPracticeExercise(req, messageInfo: {});

    expect(result.isValue, isTrue);
    expect(result.asValue!.value.toJson(), exercise().toJson());
  });

  test('an unparseable entry is a miss and is dropped', () async {
    final req = request();
    await plantLegacyEntry(req, DateTime.now(), payload: {'lang_code': 42});

    final result = await PracticeRepo.getPracticeExercise(req, messageInfo: {});

    expect(result.isError, isTrue);
    expect(raw.hasData(req.hashCode.toString()), isFalse);
  });

  test('an entry past the 1-minute TTL is a miss and is dropped', () async {
    final req = request();
    await plantLegacyEntry(
      req,
      DateTime.now().subtract(const Duration(minutes: 1, seconds: 1)),
    );

    final result = await PracticeRepo.getPracticeExercise(req, messageInfo: {});

    expect(result.isError, isTrue, reason: 'no backend here, so miss → error');
    expect(raw.hasData(req.hashCode.toString()), isFalse);
  });

  test('a fresh entry is a hit even with stale neighbours', () async {
    // The old sweep parsed every neighbour on each read; here neighbours are
    // unparseable garbage with valid timestamps, and the hit must be
    // unaffected.
    final req = request();
    await plantLegacyEntry(req, DateTime.now());
    await raw.write('garbage-live', {
      'practiceActivity': {'lang_code': 42},
      'timestamp': DateTime.now().toIso8601String(),
    });
    await raw.write('garbage-stale', {
      'practiceActivity': {'lang_code': 42},
      'timestamp': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    });

    final result = await PracticeRepo.getPracticeExercise(req, messageInfo: {});

    expect(result.isValue, isTrue);
    expect(raw.hasData('garbage-live'), isTrue);
  });

  test('invalidate drops the entry so the next read is a miss', () async {
    final req = request();
    await plantLegacyEntry(req, DateTime.now());
    expect(
      (await PracticeRepo.getPracticeExercise(req, messageInfo: {})).isValue,
      isTrue,
    );

    await PracticeRepo.invalidate(req);

    expect(raw.hasData(req.hashCode.toString()), isFalse);
    expect(
      (await PracticeRepo.getPracticeExercise(req, messageInfo: {})).isError,
      isTrue,
    );
  });
}

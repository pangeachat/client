import 'dart:io';

import 'package:flutter/services.dart';

import 'package:async/async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' hide Profile, Result;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #9151 — course-page activity card text is served in the resolved display
/// language (#8577) and [QuestRepo.outline] keys its cache on it, but nothing
/// told the course surfaces to ask again when that language changed. They kept
/// rendering the previous language's cards until the widget was rebuilt from
/// scratch. The world map already refetched on exactly these two streams
/// (#8398); this is the course-side counterpart of that trigger.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Client client;

  const questId = 'quest-1';
  const missionId = 'lo-1';
  const courseRoomId = '!course:fakeServer.notExisting';

  /// Every display language [QuestRepo.outline] was asked for, in order. The
  /// assertion subject throughout: a refetch is only a refetch if the read
  /// actually went out under the NEW language.
  late List<String> readLanguages;

  UserController user() => MatrixState.pangeaController.userController;

  /// A profile write that changed one of the learner's languages. Real ones
  /// carry the before/after models; nothing under test reads them, so the
  /// language itself is moved with [QuestRepo.debugDisplayL1].
  void emitLanguageChange() {
    final english = LanguageModel(langCode: 'en', displayName: 'English');
    final french = LanguageModel(langCode: 'fr', displayName: 'French');
    user().languageStream.add(
      LanguageUpdate(
        baseLang: french,
        targetLang: english,
        prevBaseLang: english,
        prevTargetLang: english,
      ),
    );
  }

  /// A profile write that changed no language — what the "app in target
  /// language" toggle emits, and what every other settings change emits too.
  void emitSettingsUpdate() =>
      user().settingsUpdateStream.add(Profile(userSettings: UserSettings()));

  /// One Mission over no activities. The outline's CONTENT is not what these
  /// tests assert on — [readLanguages] is — so the cheapest valid shape will
  /// do.
  void stubOutline() {
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
      readLanguages.add(QuestRepo.displayL1);
      return Result.value(
        const QuestOutline(
          quest: QuestPlan(
            id: questId,
            name: 'Quest',
            description: '',
            targetLanguage: 'de',
            sequence: [
              QuestObjectiveStep(
                objective: LearningObjective(
                  id: missionId,
                  objective: 'Can ask for directions.',
                ),
                wasMinted: false,
              ),
            ],
          ),
          groups: [],
        ),
      );
    };
  }

  /// A real [PangeaController] is what owns the two streams under test, and
  /// constructing one runs the app's own init: a language store over
  /// SharedPreferences, and a language listener that erases the GetStorage
  /// caches through path_provider. None of it is under test here — it just
  /// has to not throw — so each plugin gets the empty stand-in that lets the
  /// constructor complete (same recipe as context_language_switch_target_test).
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'outline_display_language',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init();
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    client = await getTestClient();
    readLanguages = [];
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugDisplayL1 = 'en';
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    stubOutline();
  });

  tearDown(() async {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.debugDisplayL1 = null;
    QuestRepo.resetOutlineCacheForTest();
    await client.dispose();
  });

  /// The stream hop is a microtask; the reload it starts is another.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'a base-language change re-reads the outline in the new language',
    () async {
      final loader = QuestObjectivesLoader(client: client);
      addTearDown(loader.dispose);
      await loader.loadOutline(questId, courseRoomId: courseRoomId);
      expect(readLanguages, ['en']);

      QuestRepo.debugDisplayL1 = 'fr';
      emitLanguageChange();
      await settle();

      expect(readLanguages, ['en', 'fr']);
    },
  );

  test('the "app in target language" toggle re-reads too — it changes no '
      'language but does change the resolved display one', () async {
    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);

    QuestRepo.debugDisplayL1 = 'de';
    emitSettingsUpdate();
    await settle();

    expect(readLanguages, ['en', 'de']);
  });

  test('a settings change that leaves the display language alone re-reads '
      'nothing', () async {
    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);

    // A CEFR level, a voice, a tooltip reset — every profile write lands on
    // settingsUpdateStream, and reloading the outline on each would be a read
    // per settings tap.
    emitSettingsUpdate();
    emitSettingsUpdate();
    await settle();

    expect(readLanguages, ['en']);
  });

  test('the re-read carries the original course room, so a member keeps '
      "seeing the owner's private activities", () async {
    final rooms = <String?>[];
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
      rooms.add(courseRoomId);
      readLanguages.add(QuestRepo.displayL1);
      return Result.error(MissingQuestException());
    };

    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);

    QuestRepo.debugDisplayL1 = 'fr';
    emitLanguageChange();
    await settle();

    expect(rooms, [courseRoomId, courseRoomId]);
  });

  test(
    'a language change before any outline has loaded reads nothing',
    () async {
      final loader = QuestObjectivesLoader(client: client);
      addTearDown(loader.dispose);

      QuestRepo.debugDisplayL1 = 'fr';
      emitLanguageChange();
      await settle();

      expect(readLanguages, isEmpty);
    },
  );

  test('a surface with no quest to show does not re-read the previous '
      "course's outline", () async {
    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);
    // A preview whose plan has no quest uuid — the loader lands on its
    // known-state error and has nothing to refresh.
    await loader.loadOutline(null);

    QuestRepo.debugDisplayL1 = 'fr';
    emitLanguageChange();
    await settle();

    expect(readLanguages, ['en']);
  });

  test('a disposed loader stops listening', () async {
    final loader = QuestObjectivesLoader(client: client);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);
    loader.dispose();

    QuestRepo.debugDisplayL1 = 'fr';
    emitLanguageChange();
    await settle();

    expect(readLanguages, ['en']);
  });
}

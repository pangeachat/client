import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/models/stt_translation_model.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'get_test_client.dart';

/// A learner's L1 translations follow the script of their L1: a Traditional
/// Chinese (`zh-TW`) reader is never served a Simplified (`zh`) translation,
/// while an English (US) reader still shares the `en` translation already on
/// the message.

const _simplified = '早上好';
const _traditional = '早安';

void main() {
  late Client client;
  late Room room;
  late Timeline timeline;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          for (final (code, script) in [
            ('en', 'Latn'),
            ('en-US', 'Latn'),
            ('es', 'Latn'),
            ('zh', 'Hani'),
            ('zh-CN', 'Hans'),
            ('zh-TW', 'Hant'),
            ('pa', 'Guru'),
            ('pa-Arab', 'Arab'),
          ])
            {
              'language_code': code,
              'language_name': code,
              'script': script,
              'l2_support': 'full',
            },
        ],
      }),
    });
    await PLanguageStore.initialize();
  });

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!l1:fakeServer.notExisting', client: client);
    timeline = await room.getTimeline();
  });

  tearDown(() async {
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  PangeaMessageEvent message(String eventId, Map<String, dynamic> content) =>
      PangeaMessageEvent(
        event: Event(
          type: EventTypes.Message,
          eventId: eventId,
          senderId: '@sender:fakeServer.notExisting',
          originServerTs: DateTime.now(),
          content: content,
          room: room,
        ),
        timeline: timeline,
        ownMessage: false,
      );

  Event related(String eventId, String type, Map<String, dynamic> content) =>
      Event(
        type: type,
        eventId: eventId,
        senderId: '@reader:fakeServer.notExisting',
        originServerTs: DateTime.now(),
        content: {type: content},
        room: room,
      );

  group('PLanguageStore.sameWrittenLanguage', () {
    test('a regional variant that writes like its base matches it', () {
      expect(PLanguageStore.sameWrittenLanguage('en', 'en-US'), isTrue);
      expect(PLanguageStore.sameWrittenLanguage('zh', 'zh-CN'), isTrue);
    });

    test('a script variant does not match its base language', () {
      expect(PLanguageStore.sameWrittenLanguage('zh', 'zh-TW'), isFalse);
      expect(PLanguageStore.sameWrittenLanguage('pa', 'pa-Arab'), isFalse);
      expect(PLanguageStore.sameWrittenLanguage('en', 'es'), isFalse);
    });
  });

  group('audio message translation', () {
    Future<AsyncState<String>> translate(
      String readerL1,
      Map<String, String> saved,
    ) async {
      MatrixState.pangeaController = _Reader(readerL1, 'es');
      final audio = message(r'$audio:fakeServer.notExisting', {
        'msgtype': 'm.audio',
        'body': 'recording.wav',
        'user_stt': jsonDecode(
          File(
            'test/pangea/stt_golden/choreo_response_skip_tokenize.json',
          ).readAsStringSync(),
        ),
      });
      timeline.aggregatedEvents[audio.eventId] = {
        PangeaEventTypes.sttTranslation: {
          for (final MapEntry(key: lang, value: text) in saved.entries)
            related(
              '\$stt-$lang:fakeServer.notExisting',
              PangeaEventTypes.sttTranslation,
              SttTranslationModel(translation: text, langCode: lang).toJson(),
            ),
        },
      };
      final controller = SelectModeController(audio);
      addTearDown(controller.dispose);
      await controller.fetchSpeechTranslation();
      return controller.speechTranslationState.value;
    }

    test('a Traditional Chinese reader is served the zh-TW translation', () {
      // Teeth: the short L1 code looks up `zh` and finds nothing to serve.
      expect(
        translate('zh-TW', {'zh-TW': _traditional}),
        completion(
          isA<AsyncLoaded<String>>().having(
            (s) => s.value,
            'value',
            _traditional,
          ),
        ),
      );
    });

    test('a Traditional Chinese reader is not served a zh translation', () {
      // Nothing usable is saved, so the loader goes on to fetch a new
      // translation, which fails here without a network.
      expect(
        translate('zh-TW', {'zh': _simplified}),
        completion(isA<AsyncError<String>>()),
      );
    });

    test('an English (US) reader reuses the en translation', () {
      expect(
        translate('en-US', {'en': 'good morning'}),
        completion(
          isA<AsyncLoaded<String>>().having(
            (s) => s.value,
            'value',
            'good morning',
          ),
        ),
      );
    });
  });

  group('text message translation', () {
    Future<String?> translate(Map<String, String> saved) async {
      MatrixState.pangeaController = _Reader('zh-TW', 'en');
      final text = message(r'$text:fakeServer.notExisting', {
        'msgtype': 'm.text',
        'body': 'good morning',
      });
      timeline.aggregatedEvents[text.eventId] = {
        PangeaEventTypes.representation: {
          for (final MapEntry(key: lang, value: body) in saved.entries)
            related(
              '\$rep-$lang:fakeServer.notExisting',
              PangeaEventTypes.representation,
              PangeaRepresentation(
                langCode: lang,
                text: body,
                originalSent: false,
                originalWritten: false,
              ).toJson(),
            ),
        },
      };
      try {
        return (await text.requestTranslationByL1()).bestTranslation;
      } catch (_) {
        return null; // went on to fetch a new translation
      }
    }

    test('a Traditional Chinese reader is served the zh-TW translation', () {
      expect(translate({'zh-TW': _traditional}), completion(_traditional));
    });

    test('a Traditional Chinese reader is not served a zh translation', () {
      // Teeth: matching on the base code alone serves the Simplified text.
      expect(translate({'zh': _simplified}), completion(isNull));
    });
  });
}

class _Reader implements PangeaController {
  _Reader(String l1, String l2) : userController = _ReaderSettings(l1, l2);

  @override
  final UserController userController;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ReaderSettings implements UserController {
  _ReaderSettings(this.userL1Code, this.userL2Code);

  @override
  final String userL1Code;

  @override
  final String userL2Code;

  @override
  LanguageModel? get userL1 => PLanguageStore.byLangCode(userL1Code);

  @override
  LanguageModel? get userL2 => PLanguageStore.byLangCode(userL2Code);

  @override
  bool isToolEnabled(ToolSetting setting) => false;

  /// Not logged in, so a new translation fetch fails inside the repo.
  @override
  String get accessToken => throw 'not logged in';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

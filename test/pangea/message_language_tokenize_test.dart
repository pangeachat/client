import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/utils/message_language_correction.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #8385 — the network half of re-assigning a message's language.
///
/// The tokenizer MUST be told the language the reader picked. Left to detect,
/// it reproduces the reading being corrected, and the correction ships tokens
/// from the wrong model — which is worse than not correcting at all, because
/// `correctedSent` then serves those tokens to the word cards and analytics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('msg_lang_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');

    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {'language_code': 'de', 'language_name': 'German'},
          {'language_code': 'en', 'language_name': 'English'},
        ],
      }),
    });
    await PLanguageStore.initialize();

    MatrixState.pangeaController = _ReaderController(l1: 'en', l2: 'es');
  });

  setUp(() => dotenv.testLoad(mergeWith: {'CHOREO_API': choreoApi}));

  /// The tokenize request body [MessageLanguageCorrection.tokenizeAs] puts on
  /// the wire, with the tokenizer answering a two-token reading. The text
  /// varies per call because the repo memoizes on it for 10 minutes.
  var seq = 0;
  Future<Map<String, dynamic>> capturedRequest(String langCode) async {
    late Map<String, dynamic> body;
    await http.runWithClient(
      () async {
        final tokens = await MessageLanguageCorrection.tokenizeAs(
          'buenos dias ${seq++}',
          PLanguageStore.byLangCode(langCode)!,
        );
        // The payload carries the chosen language, not whatever came back.
        expect(tokens.detections!.single.langCode, langCode);
        expect(tokens.tokens, hasLength(2));
      },
      () => MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'tokens': [
              {
                'text': {'content': 'buenos', 'offset': 0, 'length': 6},
                'lemma': {
                  'text': 'bueno',
                  'save_vocab': true,
                  'form': 'buenos',
                },
                'pos': 'ADJ',
                'morph': <String, dynamic>{},
              },
              {
                'text': {'content': 'dias', 'offset': 7, 'length': 4},
                'lemma': {'text': 'dia', 'save_vocab': true, 'form': 'dias'},
                'pos': 'NOUN',
                'morph': <String, dynamic>{},
              },
            ],
            'lang': 'es',
            'all_detections': [
              {'lang_code': 'es', 'confidence': 0.9},
            ],
          }),
          200,
        );
      }),
    );
    return body;
  }

  test('the tokenizer is told the language the reader picked', () async {
    // Teeth: drop `langCode` from the request and the tokenizer re-detects —
    // the correction would re-state the language the user is correcting.
    final body = await capturedRequest('es');
    expect(body['lang_code'], 'es');
  });

  test("the reader's own L1/L2 ride along, so save_vocab is scoped to "
      'them', () async {
    final body = await capturedRequest('es');
    expect(body['user_l1'], 'en');
    expect(body['user_l2'], 'es');
  });

  test('a different chosen language changes the request, not just the '
      'payload', () async {
    final body = await capturedRequest('de');
    expect(body['lang_code'], 'de');
  });
}

class _ReaderController implements PangeaController {
  @override
  final UserController userController;

  _ReaderController({required String l1, required String l2})
    : userController = _ReaderUserController(l1, l2);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ReaderUserController implements UserController {
  _ReaderUserController(this._l1, this._l2);

  final String _l1;
  final String _l2;

  @override
  String? get userL1Code => _l1;

  @override
  String? get userL2Code => _l2;

  @override
  LanguageModel? get userL1 => PLanguageStore.byLangCode(_l1);

  @override
  LanguageModel? get userL2 => PLanguageStore.byLangCode(_l2);

  @override
  String get accessToken => 'syt_test_token';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/utils/message_language_correction.dart';

/// #8385 — the reader re-assigns the language of a message the detector read
/// wrong, from the mode-disabled snackbar.
///
/// The two halves this covers without a network: which language the snackbar
/// and picker report as assigned, and that the correction payload actually
/// carries the chosen language through the representation the write path
/// sends. Sending itself (tokenize + `sendTokenCorrection`) is exercised
/// end-to-end by the choreo endpoint suite and manual QA.

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('correctedTokens', () {
    test('pins the chosen language at full confidence, keeping the tokens', () {
      final tokens = [_token('bom', 0), _token('dia', 4)];
      final corrected = MessageLanguageCorrection.correctedTokens(tokens, 'pt');

      expect(corrected.tokens, same(tokens));
      expect(corrected.detections, hasLength(1));
      expect(corrected.detections!.single.langCode, 'pt');
      expect(corrected.detections!.single.confidence, 1);
    });

    test('drives the language of the representation the write path sends', () {
      // Teeth: the correction's own detections are what buildTokenCorrection
      // reads. A payload that kept the old detections would send a correction
      // that re-states the wrong language and changes nothing.
      final rep = PangeaMessageEvent.buildTokenCorrection(
        fullText: 'bom dia',
        tokensSent: MessageLanguageCorrection.correctedTokens([
          _token('bom', 0),
          _token('dia', 4),
        ], 'pt'),
        fallbackLangCode: 'es',
      );

      expect(rep.langCode, 'pt');
      expect(rep.isCorrection, isTrue);
      expect(rep.tokens!.tokens, hasLength(2));
    });

    test('an empty tokenization is left empty rather than faked', () {
      // A correction without usable tokens is ignored on read, so the language
      // change must fail visibly instead of silently no-op'ing.
      final corrected = MessageLanguageCorrection.correctedTokens(
        const <PangeaToken>[],
        'pt',
      );
      expect(corrected.tokens, isEmpty);
    });
  });

  group('languageFromCode', () {
    setUpAll(() async {
      // Seed the store's cache rather than letting initialize() reach the
      // network. `pt-BR` is deliberately absent so the base-code fallback has
      // something to fall back from.
      SharedPreferences.setMockInitialValues({
        PrefKey.lastFetched: DateTime.now().toIso8601String(),
        PrefKey.languagesKey: jsonEncode({
          PrefKey.languagesKey: [
            {
              'language_code': 'es',
              'language_name': 'Spanish',
              'l2_support': 'full',
            },
            {'language_code': 'pt', 'language_name': 'Portuguese'},
          ],
        }),
      });
      await PLanguageStore.initialize();
    });

    test('resolves an exact store entry', () {
      expect(MessageLanguageCorrection.languageFromCode('es')?.langCode, 'es');
    });

    test('resolves a region-tagged code to its base language', () {
      // The mode gating compares base codes, so `pt-BR` must not read as an
      // unknown language in the snackbar the gating explains.
      expect(
        MessageLanguageCorrection.languageFromCode('pt-BR')?.langCode,
        'pt',
      );
    });

    test('is null for the unknown-language sentinel', () {
      expect(MessageLanguageCorrection.languageFromCode('unk'), isNull);
    });

    test('is null for a language the store does not carry', () {
      expect(MessageLanguageCorrection.languageFromCode('zz'), isNull);
    });
  });
}

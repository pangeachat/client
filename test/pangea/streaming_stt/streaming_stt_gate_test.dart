import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_gate.dart';

void main() {
  group('StreamingSttGate.applies (flag + widened D5 language gate)', () {
    test('flag OFF -> never streams, even for English', () {
      expect(
        StreamingSttGate.applies(
          flagEnabled: false,
          messageLangCodeShort: 'en',
        ),
        isFalse,
      );
    });

    test('flag ON + English -> streaming path', () {
      expect(
        StreamingSttGate.applies(flagEnabled: true, messageLangCodeShort: 'en'),
        isTrue,
      );
    });

    test(
      'flag ON + a widened blessed language (es) -> streaming path (D5 widen)',
      () {
        // es is now blessed/routed (T8 widen); the old English-only gate rejected it.
        expect(
          StreamingSttGate.applies(
            flagEnabled: true,
            messageLangCodeShort: 'es',
          ),
          isTrue,
        );
      },
    );

    test('applies for another D3-routed language when flag on', () {
      expect(
        StreamingSttGate.applies(flagEnabled: true, messageLangCodeShort: 'fr'),
        isTrue,
      );
    });

    test('never applies for unrouted or batch-only languages', () {
      // 'de' is NOT here: German is an owner override routed to Soniox (asserted below).
      for (final lang in <String>[
        'ar',
        'hi',
        'ja',
        'ko',
        'mn',
        'ru',
        'zh',
        'zz',
      ]) {
        expect(
          StreamingSttGate.applies(
            flagEnabled: true,
            messageLangCodeShort: lang,
          ),
          isFalse,
          reason: '$lang is not in the W3 D3 streaming table',
        );
      }
    });

    test('flag ON + German (owner override) -> streaming path', () {
      // German failed the W3 eval (Soniox empty ~1/10) but is routed to Soniox by owner
      // decision; empties degrade to batch. It must stream like any other routed language.
      expect(
        StreamingSttGate.applies(flagEnabled: true, messageLangCodeShort: 'de'),
        isTrue,
      );
      expect(
        StreamingSttGate.applies(
          flagEnabled: true,
          messageLangCodeShort: 'de-AT',
        ),
        isTrue,
        reason: 'region tags canonicalize to de',
      );
    });

    test('flag ON + unknown/null language -> batch path', () {
      expect(
        StreamingSttGate.applies(flagEnabled: true, messageLangCodeShort: null),
        isFalse,
      );
    });

    test(
      'applies canonicalizes the message language (en-US / uppercase / cmn) like the server (H7)',
      () {
        expect(
          StreamingSttGate.applies(
            flagEnabled: true,
            messageLangCodeShort: 'en-US',
          ),
          isTrue,
        );
        expect(
          StreamingSttGate.applies(
            flagEnabled: true,
            messageLangCodeShort: 'EN',
          ),
          isTrue,
        );
        // cmn still canonicalizes to zh, but zh is batch-only in the corrected table.
        expect(
          StreamingSttGate.applies(
            flagEnabled: true,
            messageLangCodeShort: 'cmn',
          ),
          StreamingSttGate.supportedLangCodesShort.contains('zh'),
        );
      },
    );

    test(
      'canonicalShort folds Chinese aliases + region tags to the route key (H7/Codex HIGH)',
      () {
        // Canonicalization remains stable even while zh is batch-only.
        expect(StreamingSttGate.canonicalShort('cmn'), 'zh');
        expect(StreamingSttGate.canonicalShort('yue'), 'zh');
        expect(StreamingSttGate.canonicalShort('zh-Hant'), 'zh');
        expect(StreamingSttGate.canonicalShort('zh-TW'), 'zh');
        expect(StreamingSttGate.canonicalShort('zh'), 'zh');
        expect(StreamingSttGate.canonicalShort('en-US'), 'en');
        expect(StreamingSttGate.canonicalShort('ES'), 'es');
        expect(StreamingSttGate.canonicalShort(null), isNull);
        expect(StreamingSttGate.canonicalShort(''), isNull);
      },
    );
  });

  group('StreamingSttGate.languageUnsupported (D11 banner trigger)', () {
    test(
      'flag OFF -> no unsupported-language banner, even for a batch-only lang',
      () {
        expect(
          StreamingSttGate.languageUnsupported(
            flagEnabled: false,
            messageLangCodeShort: 'ar',
          ),
          isFalse,
        );
      },
    );

    test(
      'flag ON + null language -> silent (unresolved L2 is NOT a language failure)',
      () {
        // Codex LOW: a not-loaded-yet target language must not be mislabeled as
        // "not available for this language" — it is the same silent no-banner
        // outcome as a flag-off session.
        expect(
          StreamingSttGate.languageUnsupported(
            flagEnabled: true,
            messageLangCodeShort: null,
          ),
          isFalse,
        );
      },
    );

    test(
      'flag ON + empty/blank language -> silent (canonicalizes to null)',
      () {
        expect(
          StreamingSttGate.languageUnsupported(
            flagEnabled: true,
            messageLangCodeShort: '',
          ),
          isFalse,
        );
        expect(
          StreamingSttGate.languageUnsupported(
            flagEnabled: true,
            messageLangCodeShort: '   ',
          ),
          isFalse,
        );
      },
    );

    test(
      'flag ON + a routed language (en/es/fr) -> no banner (streaming applies)',
      () {
        // 'de' included: German is an owner-override streaming language, so no unsupported banner.
        for (final lang in <String>['de', 'en', 'es', 'fr', 'it', 'pt']) {
          expect(
            StreamingSttGate.languageUnsupported(
              flagEnabled: true,
              messageLangCodeShort: lang,
            ),
            isFalse,
            reason:
                '$lang is routed -> streaming applies, so no unsupported banner',
          );
        }
      },
    );

    test('flag ON + a KNOWN but unrouted/batch-only language -> banner fires', () {
      // 'de' removed: German is now a routed owner-override language, not batch-only.
      for (final lang in <String>['ar', 'hi', 'ja', 'ko', 'mn', 'ru', 'zh']) {
        expect(
          StreamingSttGate.languageUnsupported(
            flagEnabled: true,
            messageLangCodeShort: lang,
          ),
          isTrue,
          reason:
              '$lang is a known language absent from the W3 D3 streaming table',
        );
      }
    });

    test(
      'flag ON + Chinese aliases fold to the batch-only zh key -> banner fires',
      () {
        for (final lang in <String>['cmn', 'yue', 'zh-Hant', 'zh-TW']) {
          expect(
            StreamingSttGate.languageUnsupported(
              flagEnabled: true,
              messageLangCodeShort: lang,
            ),
            isTrue,
            reason: '$lang canonicalizes to zh, which is batch-only',
          );
        }
      },
    );
  });
}

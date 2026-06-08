import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/text_to_speech/tts_routing.dart';

// Unit tests for the pure device-vs-backend routing logic.
// Design: client/.github/instructions/word-text-to-speech.instructions.md

Map<String, String> _voice(String name, String locale, {String? quality}) {
  final voice = {'name': name, 'locale': locale};
  if (quality != null) voice['quality'] = quality;
  return voice;
}

void main() {
  group('qualityRank', () {
    test('iOS tiers', () {
      expect(TtsRouting.qualityRank('premium'), 5);
      expect(TtsRouting.qualityRank('enhanced'), 4);
      expect(TtsRouting.qualityRank('default'), 2);
    });

    test('Android tiers (note the spaces)', () {
      expect(TtsRouting.qualityRank('very high'), 5);
      expect(TtsRouting.qualityRank('high'), 4);
      expect(TtsRouting.qualityRank('normal'), 3);
      expect(TtsRouting.qualityRank('low'), 1);
      expect(TtsRouting.qualityRank('very low'), 0);
    });

    test('case-insensitive and unknown/null default to mid', () {
      expect(TtsRouting.qualityRank('ENHANCED'), 4);
      expect(TtsRouting.qualityRank(null), 2);
      expect(TtsRouting.qualityRank(''), 2);
      expect(TtsRouting.qualityRank('something-weird'), 2);
    });

    test('good threshold is enhanced/high and above', () {
      expect(TtsRouting.qualityRank('enhanced'), greaterThanOrEqualTo(TtsRouting.nativeGoodQualityRank));
      expect(TtsRouting.qualityRank('high'), greaterThanOrEqualTo(TtsRouting.nativeGoodQualityRank));
      expect(TtsRouting.qualityRank('normal'), lessThan(TtsRouting.nativeGoodQualityRank));
      expect(TtsRouting.qualityRank('default'), lessThan(TtsRouting.nativeGoodQualityRank));
    });
  });

  group('isGoodWebVoiceName', () {
    test('matches known-good vendor markers', () {
      expect(TtsRouting.isGoodWebVoiceName('Google Deutsch'), isTrue);
      expect(TtsRouting.isGoodWebVoiceName('Microsoft Seraphina Online (Natural)'), isTrue);
      expect(TtsRouting.isGoodWebVoiceName('Anna (Enhanced)'), isTrue);
      expect(TtsRouting.isGoodWebVoiceName('Anna (Premium)'), isTrue);
    });

    test('rejects flat / novelty voices', () {
      expect(TtsRouting.isGoodWebVoiceName('Anna'), isFalse);
      expect(TtsRouting.isGoodWebVoiceName('Helena'), isFalse);
      expect(TtsRouting.isGoodWebVoiceName('Grandpa (German (Germany))'), isFalse);
    });

    test('is case-insensitive', () {
      expect(TtsRouting.isGoodWebVoiceName('GOOGLE DEUTSCH'), isTrue);
    });
  });

  group('selectVoice — web (name patterns)', () {
    final germanVoices = [
      _voice('Anna', 'de-DE'),
      _voice('Helena', 'de-DE'),
      _voice('Google Deutsch', 'de-DE'),
    ];

    test('picks the good-named voice over flat ones', () {
      final s = TtsRouting.selectVoice(germanVoices, 'de-DE', isWeb: true);
      expect(s.hasVoice, isTrue);
      expect(s.isKnownGood, isTrue);
      expect(s.voice?['name'], 'Google Deutsch');
    });

    test('only flat voices: hasVoice but not known-good, falls to first candidate', () {
      final s = TtsRouting.selectVoice(
        [_voice('Anna', 'de-DE'), _voice('Helena', 'de-DE')],
        'de-DE',
        isWeb: true,
      );
      expect(s.hasVoice, isTrue);
      expect(s.isKnownGood, isFalse);
      expect(s.voice?['name'], 'Anna');
    });

    test('no voice for the language', () {
      final s = TtsRouting.selectVoice(germanVoices, 'el-GR', isWeb: true);
      expect(s.hasVoice, isFalse);
      expect(s.isKnownGood, isFalse);
      expect(s.voice, isNull);
    });

    test('matches by base-language prefix and bare code', () {
      expect(TtsRouting.selectVoice(germanVoices, 'de', isWeb: true).isKnownGood, isTrue);
      expect(TtsRouting.selectVoice(germanVoices, 'DE-de', isWeb: true).hasVoice, isTrue);
    });

    test('web ignores the quality field entirely', () {
      // A high-quality flat-named voice is still not "good" on web.
      final s = TtsRouting.selectVoice(
        [_voice('Anna', 'de-DE', quality: 'very high')],
        'de-DE',
        isWeb: true,
      );
      expect(s.isKnownGood, isFalse);
    });
  });

  group('selectVoice — native (quality field)', () {
    test('picks highest-quality voice and marks it good', () {
      final s = TtsRouting.selectVoice(
        [
          _voice('Anna', 'de-DE', quality: 'default'),
          _voice('Markus', 'de-DE', quality: 'enhanced'),
        ],
        'de-DE',
        isWeb: false,
      );
      expect(s.voice?['name'], 'Markus');
      expect(s.isKnownGood, isTrue);
    });

    test('only low-tier voices: has voice but not good', () {
      final s = TtsRouting.selectVoice(
        [
          _voice('Anna', 'de-DE', quality: 'default'),
          _voice('Eddy', 'de-DE', quality: 'low'),
        ],
        'de-DE',
        isWeb: false,
      );
      expect(s.hasVoice, isTrue);
      expect(s.isKnownGood, isFalse);
      expect(s.voice?['name'], 'Anna'); // 'default'(2) outranks 'low'(1)
    });

    test('native ignores the name patterns', () {
      // A Google-named voice with no/low quality is not auto-good on native.
      final s = TtsRouting.selectVoice(
        [_voice('Google Deutsch', 'de-DE', quality: 'low')],
        'de-DE',
        isWeb: false,
      );
      expect(s.isKnownGood, isFalse);
    });
  });

  group('useBackend', () {
    const good = TtsVoiceSelection(
      voice: {'name': 'Google Deutsch', 'locale': 'de-DE'},
      isKnownGood: true,
      hasVoice: true,
    );
    const flat = TtsVoiceSelection(
      voice: {'name': 'Anna', 'locale': 'de-DE'},
      isKnownGood: false,
      hasVoice: true,
    );
    const none = TtsVoiceSelection(voice: null, isKnownGood: false, hasVoice: false);

    test('known-good device voice → device, regardless of subscription', () {
      expect(TtsRouting.useBackend(hasPhoneme: false, selection: good, isSubscribed: true), isFalse);
      expect(TtsRouting.useBackend(hasPhoneme: false, selection: good, isSubscribed: false), isFalse);
    });

    test('flat device voice → backend only if subscribed', () {
      expect(TtsRouting.useBackend(hasPhoneme: false, selection: flat, isSubscribed: true), isTrue);
      expect(TtsRouting.useBackend(hasPhoneme: false, selection: flat, isSubscribed: false), isFalse);
    });

    test('no device voice → backend only if subscribed', () {
      expect(TtsRouting.useBackend(hasPhoneme: false, selection: none, isSubscribed: true), isTrue);
      expect(TtsRouting.useBackend(hasPhoneme: false, selection: none, isSubscribed: false), isFalse);
    });

    test('phoneme override → backend if subscribed, even with a good device voice', () {
      expect(TtsRouting.useBackend(hasPhoneme: true, selection: good, isSubscribed: true), isTrue);
      // free user cannot use backend, so a phoneme request falls through to device
      expect(TtsRouting.useBackend(hasPhoneme: true, selection: good, isSubscribed: false), isFalse);
    });
  });
}

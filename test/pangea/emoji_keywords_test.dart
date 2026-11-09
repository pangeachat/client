import 'package:flutter/widgets.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/chat/emoji_keywords.dart';

/// #9412 — the composer's `:keyword` emoji suggestions match keywords in the
/// app's language and in the learner's target language (L2).
void main() {
  LanguageModel language(String code) =>
      LanguageModel(langCode: code, displayName: code);

  List<Emoji> suggestions(
    String search, {
    required String appLanguage,
    String? targetLanguage,
  }) => EmojiKeywords.suggestionsFor(
    search,
    appLanguageEmojis: [
      for (final category in getDefaultEmojiLocale(Locale(appLanguage)))
        ...category.emoji,
    ],
    targetLanguage: targetLanguage == null ? null : language(targetLanguage),
  );

  List<String> suggestedEmojis(
    String search, {
    required String appLanguage,
    String? targetLanguage,
  }) => suggestions(
    search,
    appLanguage: appLanguage,
    targetLanguage: targetLanguage,
  ).map((emoji) => emoji.emoji).toList();

  group('suggestionsFor', () {
    test('suggests an emoji by its target-language keyword', () {
      expect(
        suggestedEmojis('кот', appLanguage: 'en', targetLanguage: 'ru'),
        contains('🐱'),
      );
    });

    test('still suggests an emoji by its app-language keyword', () {
      expect(
        suggestedEmojis('kitten', appLanguage: 'en', targetLanguage: 'ru'),
        contains('🐱'),
      );
    });

    test('suggests an emoji once when both languages match it', () {
      expect(
        suggestedEmojis('pizza', appLanguage: 'en', targetLanguage: 'es'),
        ['🍕'],
      );
    });

    test('keeps the keywords where the search comes earliest', () {
      expect(
        suggestions(
          'pizza',
          appLanguage: 'en',
          targetLanguage: 'es',
        ).single.name,
        startsWith('pizza'),
      );
    });

    test('suggests an emoji the picker files under two categories once', () {
      expect(
        suggestedEmojis('luggage', appLanguage: 'en').where((e) => e == '🧳'),
        hasLength(1),
      );
    });

    test('a regional target language uses its language\'s keywords', () {
      expect(
        suggestedEmojis('gato', appLanguage: 'en', targetLanguage: 'es-MX'),
        contains('🐱'),
      );
    });

    test('a target language the picker has no keywords in adds none', () {
      expect(
        suggestedEmojis('kitten', appLanguage: 'es', targetLanguage: 'ko'),
        isEmpty,
      );
    });
  });

  group('setFor', () {
    test('a language the picker has no keywords in gives none', () {
      expect(EmojiKeywords.setFor(const Locale('ko')), isEmpty);
    });

    test('English gives the English keywords', () {
      expect(EmojiKeywords.setFor(const Locale('en')), same(emojiSetEnglish));
    });
  });
}

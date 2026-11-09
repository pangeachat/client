import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';

import 'package:fluffychat/features/languages/language_model.dart';

/// The emoji picker package's keywords, which the chat searches in the app's
/// language and in the learner's target language.
class EmojiKeywords {
  /// The language [getDefaultEmojiLocale] answers with for a language it has
  /// no keywords in.
  static const _fallbackLanguageCode = 'en';

  /// The package's emojis with keywords in [locale]'s language, or none when it
  /// has no keywords in that language, rather than its English fallback.
  static List<CategoryEmoji> setFor(Locale locale) {
    final emojiSet = getDefaultEmojiLocale(locale);
    return identical(emojiSet, emojiSetEnglish) &&
            locale.languageCode != _fallbackLanguageCode
        ? const []
        : emojiSet;
  }

  /// The composer's `:keyword` suggestions: emojis whose keywords, in the app's
  /// language or [targetLanguage], contain [search]. Earliest match first.
  static List<Emoji> suggestionsFor(
    String search, {
    required List<Emoji> appLanguageEmojis,
    required LanguageModel? targetLanguage,
  }) {
    final term = search.toLowerCase();
    final matches = [
      ...appLanguageEmojis,
      if (targetLanguage != null)
        for (final category in setFor(targetLanguage.locale)) ...category.emoji,
    ].where((emoji) => emoji.name.toLowerCase().contains(term)).toList();
    // Thanks for the hint by github.com/nextcloud/circles devs.
    mergeSort(
      matches,
      compare: (a, b) => a.name
          .toLowerCase()
          .indexOf(term)
          .compareTo(b.name.toLowerCase().indexOf(term)),
    );
    final suggestedEmojis = <String>{};
    return matches.where((emoji) => suggestedEmojis.add(emoji.emoji)).toList();
  }
}

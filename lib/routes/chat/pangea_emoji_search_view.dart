import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/chat/emoji_keywords.dart';

class PangeaEmojiSearchView extends SearchView {
  const PangeaEmojiSearchView(
    super.config,
    super.state,
    super.showEmojiView, {
    required this.targetLanguage,
    super.key,
  });

  /// Search also matches emojis by their keywords in this language.
  final LanguageModel? targetLanguage;

  @override
  PangeaEmojiSearchViewState createState() => PangeaEmojiSearchViewState();
}

class PangeaEmojiSearchViewState
    extends SearchViewState<PangeaEmojiSearchView> {
  String? _targetKeywordsLanguageCode;
  Map<String, Set<String>> _targetKeywordsByEmoji = const {};

  /// Not [EmojiPickerUtils.searchEmoji]: it keeps the first emoji set it is
  /// given for the session, so no second or changed language reaches it.
  @override
  void onTextInputChanged(String text) {
    final matches = _search(text);
    setState(() {
      links.clear();
      results
        ..clear()
        ..addAll(matches);
    });
  }

  /// The picker's emojis, once each and in picker order, that are [text] or
  /// have a keyword starting with each word of it, in either language.
  List<Emoji> _search(String text) {
    final searchWords = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toSet();
    if (searchWords.isEmpty) return [];

    final targetKeywordsByEmoji = _targetKeywords();
    final matchedEmojis = <String>{};
    final matches = <Emoji>[];
    for (final category in widget.state.categoryEmoji) {
      if (category.category == Category.RECENT) continue;
      for (final emoji in category.emoji) {
        final keywords = {
          ...emoji.keywords.map((keyword) => keyword.toLowerCase()),
          ...?targetKeywordsByEmoji[emoji.emoji],
        };
        final isMatch =
            emoji.emoji == text.trim() ||
            searchWords.every(
              (word) => keywords.any((keyword) => keyword.startsWith(word)),
            );
        if (isMatch && matchedEmojis.add(emoji.emoji)) matches.add(emoji);
      }
    }
    return matches;
  }

  Map<String, Set<String>> _targetKeywords() {
    final locale = widget.targetLanguage?.locale;
    if (locale?.languageCode != _targetKeywordsLanguageCode) {
      _targetKeywordsLanguageCode = locale?.languageCode;
      _targetKeywordsByEmoji = locale == null
          ? const {}
          : _keywordsByEmoji(locale);
    }
    return _targetKeywordsByEmoji;
  }

  static Map<String, Set<String>> _keywordsByEmoji(Locale locale) => {
    for (final category in EmojiKeywords.setFor(locale))
      for (final emoji in category.emoji)
        emoji.emoji: emoji.keywords
            .map((keyword) => keyword.toLowerCase())
            .toSet(),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize = widget.config.emojiViewConfig.getEmojiSize(
          constraints.maxWidth,
        );
        final emojiBoxSize = widget.config.emojiViewConfig.getEmojiBoxSize(
          constraints.maxWidth,
        );

        return Container(
          color: widget.config.searchViewConfig.backgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () {
                      widget.showEmojiView();
                    },
                    color: widget.config.searchViewConfig.buttonIconColor,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: TextField(
                      onChanged: onTextInputChanged,
                      focusNode: focusNode,
                      style: widget.config.searchViewConfig.inputTextStyle,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: widget.config.searchViewConfig.hintText,
                        hintStyle: widget.config.searchViewConfig.hintTextStyle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Material(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  child: EmojiContainer(
                    color: widget.config.emojiViewConfig.backgroundColor,
                    buttonMode: widget.config.emojiViewConfig.buttonMode,
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        childAspectRatio: 1,
                        crossAxisCount: widget.config.emojiViewConfig.columns,
                        mainAxisSpacing:
                            widget.config.emojiViewConfig.verticalSpacing,
                        crossAxisSpacing:
                            widget.config.emojiViewConfig.horizontalSpacing,
                      ),
                      scrollDirection: Axis.vertical,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        return buildEmoji(
                          results[index],
                          emojiSize,
                          emojiBoxSize,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

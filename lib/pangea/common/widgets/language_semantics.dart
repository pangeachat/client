import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/languages/language_constants.dart';

/// Tells screen readers which language [child]'s text is in, so they read it
/// in that language's voice rather than the UI's (WCAG 3.1.2).
///
/// A semantics container, so the language stays on this text and does not
/// reach the labels merged around it (a sender name, a timestamp). A missing
/// or unknown [langCode] leaves [child] unmarked, read in the UI voice.
class LanguageSemantics extends StatelessWidget {
  final String? langCode;
  final Widget child;

  const LanguageSemantics({
    super.key,
    required this.langCode,
    required this.child,
  });

  /// The locale a screen reader should read [langCode] text in, or null when
  /// the language is missing or unknown.
  static Locale? localeOf(String? langCode) {
    final language = langCode?.split(RegExp('[-_]')).first.toLowerCase();
    if (language == null ||
        language.isEmpty ||
        language == LanguageKeys.unknownLanguage) {
      return null;
    }
    // ponytail: language only. The web engine writes `lang` with an
    // underscore (es_MX), which is not a valid tag; pass the region once it
    // writes toLanguageTag.
    return Locale(language);
  }

  /// [label] with the first occurrence of [part] marked as [langCode], for a
  /// control whose one name mixes a word in another language with UI copy
  /// ("bien, Seeds, new words"). iOS and Android voice the range in that
  /// language; the web engine ignores per-range language and reads the whole
  /// name in the UI voice.
  static AttributedString labelWithPart(
    String label, {
    required String part,
    required String? langCode,
  }) {
    final locale = localeOf(langCode);
    final start = part.isEmpty ? -1 : label.indexOf(part);
    if (locale == null || start < 0) return AttributedString(label);
    return AttributedString(
      label,
      attributes: [
        LocaleStringAttribute(
          range: TextRange(start: start, end: start + part.length),
          locale: locale,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = localeOf(langCode);
    // Always a Semantics, even when unmarked, so a language arriving later
    // (detection finishing) doesn't remount the text under it.
    return Semantics(
      container: locale != null,
      localeForSubtree: locale,
      child: child,
    );
  }
}

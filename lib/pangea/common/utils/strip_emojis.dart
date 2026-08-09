import 'package:characters/characters.dart';

/// Removes emoji glyphs from [text] while preserving every script we teach
/// (Latin diacritics, Greek, Cyrillic, Hebrew, Arabic, Devanagari, Bengali,
/// Gurmukhi, Ge'ez, Thai, CJK, Hiragana/Katakana, Hangul, Vietnamese tones).
///
/// Used to clean text before TTS playback: synthesizers verbalize emoji as
/// their localized name ("waving hand", "pizza"), which is confusing in
/// language-learning audio. Server-side equivalent: choreo PR #2070 (closes
/// pangeachat/2-step-choreographer#2053). This client-side strip covers paths
/// the server fix doesn't: device flutter_tts and mixed-content tokens.
///
/// Detection iterates grapheme clusters so ZWJ family sequences (👨‍👩‍👧),
/// skin-tone modifiers, variation selectors, and keycap combinations are
/// dropped together with the base glyph. A grapheme is treated as emoji if
/// any of its runes is `Extended_Pictographic`, a regional-indicator half
/// (flag emoji), a skin-tone modifier, or the keycap combining mark.
///
/// `Extended_Pictographic` is the right property here: it's "this codepoint
/// is meant to render as a picture," and unlike `\p{Emoji}` it excludes
/// ASCII digits and `#`/`*`. Combined with the keycap-mark check, sequences
/// like `0️⃣` are dropped while bare `0` survives.
///
/// Whitespace runs introduced by removal are collapsed, and the result is
/// trimmed.
String stripEmojis(String text) {
  if (text.isEmpty) return text;

  final out = StringBuffer();
  for (final grapheme in text.characters) {
    if (_graphemeIsEmoji(grapheme)) continue;
    out.write(grapheme);
  }

  return out.toString().replaceAll(_whitespaceRun, ' ').trim();
}

bool _graphemeIsEmoji(String grapheme) => _emojiSignal.hasMatch(grapheme);

final String _emojiSignalPattern = [
  // Regional indicators (flag-emoji halves): not Extended_Pictographic.
  r'[\u{1F1E6}-\u{1F1FF}]',
  // Keycap combining mark: turns 0-9, #, * into emoji when joined.
  r'|\u{20E3}',
  // Skin-tone modifiers: only ever appear on emoji bases.
  r'|[\u{1F3FB}-\u{1F3FF}]',
  // Canonical "renders as a picture" property (excludes plain digits/#/*).
  r'|\p{Extended_Pictographic}',
].join();

final RegExp _emojiSignal = RegExp(_emojiSignalPattern, unicode: true);

final RegExp _whitespaceRun = RegExp(r'\s+');

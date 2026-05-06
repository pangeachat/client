import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/strip_emojis.dart';

/// Coverage matrix for [stripEmojis].
///
/// Two invariants we must hold across every supported L2:
/// 1. Emoji glyphs (and their joiners / modifiers / variation selectors) are
///    fully removed, so no TTS engine can verbalize their localized name.
/// 2. Letters, marks, digits, and punctuation in the L2 script are preserved
///    byte-for-byte. We do NOT do any case-folding or diacritic stripping;
///    that's the job of `normalizeString`, not this util.
///
/// Each language block has a "no emoji → unchanged" case and an "emoji
/// inserted → preserves L2 chars" case. Emoji-mechanic tests (skin tone,
/// ZWJ, regional indicators, keycap, variation selectors) are grouped at
/// the bottom since they're orthogonal to language.
void main() {
  group('stripEmojis: preserves L2 across scripts', () {
    final cases = <_Case>[
      // Latin scripts with diacritics: must be preserved verbatim.
      _Case('en: no emoji', 'Hello world!', 'Hello world!'),
      _Case('en: single emoji mid-text', 'Hello 👋 world', 'Hello world'),
      _Case('en: leading emoji', '👋 hi', 'hi'),
      _Case('en: trailing emoji', 'bye 👋', 'bye'),
      _Case('en: emoji adjacent to punctuation', 'I love pizza 🍕!', 'I love pizza !'),
      _Case('es: diacritics + emoji', '¡Hola, España! 🇪🇸', '¡Hola, España!'),
      _Case('es: ñ preserved', 'Mañana 😀 será', 'Mañana será'),
      _Case('fr: accents preserved', 'Café 🇫🇷 préféré', 'Café préféré'),
      _Case('fr: ç preserved', 'garçon 😀', 'garçon'),
      _Case('de: umlauts + ß preserved', 'Schöne Grüße 👍 München', 'Schöne Grüße München'),
      _Case('de: ß alone with emoji', 'Straße 🚗', 'Straße'),
      _Case('it: accents preserved', 'È così! 🍝', 'È così!'),
      _Case('pt: tildes preserved', 'São Paulo 🇧🇷', 'São Paulo'),
      _Case('ca: diacritics preserved', 'això és 😀 bo', 'això és bo'),
      _Case('vi: tone marks preserved', 'tiếng Việt 🇻🇳 đẹp', 'tiếng Việt đẹp'),
      _Case('tr: dotted/dotless I preserved', 'İstanbul şehri 🌆', 'İstanbul şehri'),
      _Case('cs: háček preserved', 'Děkuji 😊 moc', 'Děkuji moc'),
      _Case('pl: ogonek preserved', 'Dziękuję 🙏 bardzo', 'Dziękuję bardzo'),
      _Case('ro: comma-below preserved', 'București 🇷🇴 mare', 'București mare'),

      // Nordic: tricky because ø is U+00F8 (Latin-1 Supplement); make sure
      // it's not in any emoji range we accidentally over-match.
      _Case('da: æøå preserved', 'København 🇩🇰 byen', 'København byen'),
      _Case('sv: åäö preserved', 'Göteborg 🇸🇪 stan', 'Göteborg stan'),
      _Case('no: æøå preserved', 'fjell 🏔️ og hav', 'fjell og hav'),

      // Greek
      _Case('el: Greek letters preserved', 'Γεια σας! 👋', 'Γεια σας!'),
      _Case('el: accented Greek preserved', 'Αθήνα 🏛️ είναι', 'Αθήνα είναι'),

      // Cyrillic
      _Case('ru: Russian preserved', 'Привет мир! 🌍', 'Привет мир!'),
      _Case('uk: Ukrainian preserved', 'Слава 🇺🇦 Україні', 'Слава Україні'),
      _Case('bg: Bulgarian preserved', 'Здравей 👋 свят', 'Здравей свят'),
      _Case('sr: Serbian preserved', 'Београд 🇷🇸 град', 'Београд град'),

      // Right-to-left scripts: the strip must not flip or mangle order.
      _Case('ar: Arabic preserved', 'مرحبا 👋 بالعالم', 'مرحبا بالعالم'),
      _Case('ar: diacritized Arabic preserved', 'مرحباً 😊', 'مرحباً'),
      _Case('he: Hebrew preserved', 'שלום 🕊️ עולם', 'שלום עולם'),
      _Case('fa: Persian preserved', 'سلام 👋 دنیا', 'سلام دنیا'),
      _Case('ur: Urdu preserved', 'السلام علیکم 🌙', 'السلام علیکم'),

      // Indic scripts: combining marks (matras) must stay attached to bases.
      _Case('hi: Devanagari preserved', 'नमस्ते 🙏 दुनिया', 'नमस्ते दुनिया'),
      _Case('hi: conjuncts preserved', 'विद्यालय 📚', 'विद्यालय'),
      _Case('mr: Marathi preserved', 'नमस्कार 🙏', 'नमस्कार'),
      _Case('bn: Bengali preserved', 'নমস্কার 🙏 বিশ্ব', 'নমস্কার বিশ্ব'),
      _Case('gu: Gujarati preserved', 'નમસ્તે 🙏', 'નમસ્તે'),
      _Case('kn: Kannada preserved', 'ನಮಸ್ಕಾರ 🙏', 'ನಮಸ್ಕಾರ'),
      _Case('pa: Gurmukhi preserved', 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ 🙏', 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ'),

      // Other non-Latin scripts
      _Case('th: Thai preserved', 'สวัสดี 🙏 ครับ', 'สวัสดี ครับ'),
      _Case('am: Amharic preserved', 'ሰላም 👋 ዓለም', 'ሰላም ዓለም'),

      // CJK + Japanese + Korean: make sure ideographs and Hangul survive.
      _Case('zh: Chinese preserved', '你好 👋 世界', '你好 世界'),
      _Case('zh: punctuation preserved', '中文！😀', '中文！'),
      _Case('ja: mixed kana + kanji + emoji', 'こんにちは 👋 世界', 'こんにちは 世界'),
      _Case('ja: katakana preserved', 'コンピュータ 💻', 'コンピュータ'),
      _Case('ko: Hangul preserved', '안녕하세요 👋 세계', '안녕하세요 세계'),
      _Case('ko: Hangul Jamo composition preserved', '한국어 🇰🇷', '한국어'),
    ];

    for (final c in cases) {
      test(c.name, () {
        expect(stripEmojis(c.input), equals(c.expected));
      });
    }
  });

  group('stripEmojis: emoji mechanics', () {
    test('returns empty string unchanged', () {
      expect(stripEmojis(''), '');
    });

    test('whitespace-only input becomes empty after trim', () {
      expect(stripEmojis('   '), '');
    });

    test('pure-emoji message becomes empty', () {
      expect(stripEmojis('👋🌍'), '');
    });

    test('strips ZWJ family sequence as one unit', () {
      // 👨‍👩‍👧 = man + ZWJ + woman + ZWJ + girl. Must drop entirely; must not
      // leave orphan ZWJs or partial silhouettes behind.
      expect(stripEmojis('Family 👨‍👩‍👧 photo'), 'Family photo');
    });

    test('strips skin-tone modified emoji as one unit', () {
      expect(stripEmojis('Wave 👋🏽 hello'), 'Wave hello');
    });

    test('strips regional-indicator flag pairs', () {
      expect(stripEmojis('Visit 🇺🇸 today'), 'Visit today');
      expect(stripEmojis('🇺🇸🇪🇸🇫🇷 flags'), 'flags');
    });

    test('strips keycap sequences (digit + VS16 + U+20E3)', () {
      // 0️⃣ would otherwise leak through a naive Extended_Pictographic check
      // because the base "0" is not Extended_Pictographic. The keycap mark
      // U+20E3 in the cluster triggers the strip.
      expect(stripEmojis('Pick 0️⃣'), 'Pick');
      expect(stripEmojis('1️⃣ then 2️⃣'), 'then');
    });

    test('preserves bare digits without keycap', () {
      // No keycap mark → not emoji. Plain digits must survive.
      expect(stripEmojis('Year 2026 starts'), 'Year 2026 starts');
    });

    test('preserves # and * without keycap', () {
      expect(stripEmojis('use #tag and *bold*'), 'use #tag and *bold*');
    });

    test('strips text-style symbols when followed by VS16 (emoji presentation)', () {
      // ✈ is Extended_Pictographic; with or without VS16 we should drop it.
      expect(stripEmojis('book ✈️ ticket'), 'book ticket');
      expect(stripEmojis('book ✈ ticket'), 'book ticket');
    });

    test('strips dingbat-range emoji (✨ ❤ ⭐)', () {
      expect(stripEmojis('shine ✨ bright'), 'shine bright');
      expect(stripEmojis('I ❤️ you'), 'I you');
      expect(stripEmojis('rate ⭐⭐⭐'), 'rate');
    });

    test('strips supplemental-pictographs-A (🦄 🧠 🥑)', () {
      expect(stripEmojis('🦄 unicorn 🧠 brain 🥑 avo'), 'unicorn brain avo');
    });

    test('strips extended-A symbols (🪐 🫶 🩷)', () {
      expect(stripEmojis('orbit 🪐 the sun'), 'orbit the sun');
      expect(stripEmojis('hold 🫶 close'), 'hold close');
    });

    test('strips back-to-back emoji without leaving doubled spaces', () {
      // "👋👋👋 hi" → after strip, single leading-space-trim → "hi".
      expect(stripEmojis('👋👋👋 hi'), 'hi');
      // "a 👋👋 b" → collapses to single space.
      expect(stripEmojis('a 👋👋 b'), 'a b');
    });

    test('collapses whitespace runs created by emoji removal', () {
      expect(stripEmojis('foo   👋   bar'), 'foo bar');
    });

    test('preserves embedded newlines but collapses around stripped emoji', () {
      // \s+ in our collapse pattern matches newlines too: that's fine for TTS,
      // which doesn't care about line structure.
      expect(stripEmojis('line1\n👋\nline2'), 'line1 line2');
    });

    test('does not strip non-emoji symbols that share blocks with emoji', () {
      // Currency, math, and arrow signs that are not Extended_Pictographic
      // must survive: they're language-relevant.
      expect(stripEmojis(r'Price: $5 + €4 = ¥900'), r'Price: $5 + €4 = ¥900');
      expect(stripEmojis('a < b > c'), 'a < b > c');
    });

    test('does not strip Latin combining diacritics', () {
      // "é" composed as e + U+0301 (combining acute). Must survive intact.
      const composed = 'café';
      expect(stripEmojis(composed), composed);
    });

    test('does not strip Devanagari combining matras', () {
      // "हिन्दी" uses U+093F (i-matra) and U+094D (virama).
      const hindi = 'हिन्दी';
      expect(stripEmojis(hindi), hindi);
    });

    test('does not strip Arabic harakat', () {
      // مَرْحَبًا includes fatha, sukun, fatha, fathatan.
      const arabic = 'مَرْحَبًا';
      expect(stripEmojis(arabic), arabic);
    });
  });
}

class _Case {
  _Case(this.name, this.input, this.expected);
  final String name;
  final String input;
  final String expected;
}

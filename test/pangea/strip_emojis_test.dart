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
      _Case(
        'en: emoji adjacent to punctuation',
        'I love pizza 🍕!',
        'I love pizza !',
      ),
      _Case('es: diacritics + emoji', '¡Hola, España! 🇪🇸', '¡Hola, España!'),
      _Case('es: ñ preserved', 'Mañana 😀 será', 'Mañana será'),
      _Case('fr: accents preserved', 'Café 🇫🇷 préféré', 'Café préféré'),
      _Case('fr: ç preserved', 'garçon 😀', 'garçon'),
      _Case(
        'de: umlauts + ß preserved',
        'Schöne Grüße 👍 München',
        'Schöne Grüße München',
      ),
      _Case('de: ß alone with emoji', 'Straße 🚗', 'Straße'),
      _Case('it: accents preserved', 'È così! 🍝', 'È così!'),
      _Case('pt: tildes preserved', 'São Paulo 🇧🇷', 'São Paulo'),
      _Case('ca: diacritics preserved', 'això és 😀 bo', 'això és bo'),
      _Case(
        'vi: tone marks preserved',
        'tiếng Việt 🇻🇳 đẹp',
        'tiếng Việt đẹp',
      ),
      _Case(
        'tr: dotted/dotless I preserved',
        'İstanbul şehri 🌆',
        'İstanbul şehri',
      ),
      _Case('cs: háček preserved', 'Děkuji 😊 moc', 'Děkuji moc'),
      _Case('pl: ogonek preserved', 'Dziękuję 🙏 bardzo', 'Dziękuję bardzo'),
      _Case(
        'ro: comma-below preserved',
        'București 🇷🇴 mare',
        'București mare',
      ),
      _Case(
        'hu: double-acute ő ű preserved',
        'Köszönöm 🙏 szépen',
        'Köszönöm szépen',
      ),
      _Case('sk: caron on l preserved', 'Ďakujem 🙏 veľmi', 'Ďakujem veľmi'),
      _Case('et: õ preserved', 'Tere 👋 hommikust', 'Tere hommikust'),
      _Case('fi: åäö preserved', 'Hyvää päivää 😀', 'Hyvää päivää'),
      _Case('lt: ą č ę ė į š ų ū ž preserved', 'Ačiū 🙏 už', 'Ačiū už'),
      _Case('lv: macron preserved', 'Sveiki 👋 draugi', 'Sveiki draugi'),
      _Case('eu: Basque preserved', 'Kaixo 👋 mundua', 'Kaixo mundua'),
      _Case('gl: Galician preserved', 'Bo día 🌅', 'Bo día'),
      _Case('id: Indonesian (pure Latin)', 'Selamat 👋 pagi', 'Selamat pagi'),
      _Case('ms: Malay preserved', 'Selamat 👋 datang', 'Selamat datang'),
      _Case(
        'nl: diaeresis preserved',
        'Goedemorgen 🌅 ïn België',
        'Goedemorgen ïn België',
      ),

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
      // Mongolian Cyrillic adds Ө (U+04E8) and Ү (U+04AE) to the basic block.
      _Case(
        'mn: Mongolian Cyrillic Ө/Ү preserved',
        'Сайн 👋 байна уу',
        'Сайн байна уу',
      ),

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
      _Case('zh-TW: Traditional preserved', '繁體中文 🇹🇼', '繁體中文'),
      // Cantonese uses Traditional Han plus distinctive chars like 嘅 哋 喺.
      _Case('yue: Cantonese-specific chars preserved', '你好 嘅 👋 朋友', '你好 嘅 朋友'),
      _Case('ja: mixed kana + kanji + emoji', 'こんにちは 👋 世界', 'こんにちは 世界'),
      _Case('ja: katakana preserved', 'コンピュータ 💻', 'コンピュータ'),
      _Case('ja: half-width katakana preserved', 'ｺﾝﾆﾁﾊ 👋', 'ｺﾝﾆﾁﾊ'),
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

    test('strips * and # keycap sequences', () {
      // *️⃣ and #️⃣ are valid keycap emoji. Bases (* and #) are NOT
      // Extended_Pictographic, but the U+20E3 keycap mark in the cluster
      // triggers the strip just like for digit keycaps.
      expect(stripEmojis('Press *️⃣ to repeat'), 'Press to repeat');
      expect(stripEmojis('use #️⃣ key'), 'use key');
    });

    test('strips ZWJ profession sequences (skin tone + ZWJ + role)', () {
      // 🧑🏽‍🎓 = person + medium skin tone + ZWJ + graduation cap.
      // Stresses three mechanics in one cluster: ZWJ, skin tone, multi-emoji.
      expect(stripEmojis('Meet 🧑🏽‍🎓 grad'), 'Meet grad');
      // 👩‍⚕️ = woman + ZWJ + medical symbol + VS16.
      expect(stripEmojis('our 👩‍⚕️ helped'), 'our helped');
    });

    test('strips ZWJ-built flags (pride, trans)', () {
      // 🏳️‍🌈 = white flag + VS16 + ZWJ + rainbow. Different mechanism from
      // regional-indicator flag pairs (🇺🇸).
      expect(stripEmojis('rainbow 🏳️‍🌈 day'), 'rainbow day');
      // 🏳️‍⚧️ = white flag + VS16 + ZWJ + transgender symbol + VS16.
      expect(stripEmojis('show 🏳️‍⚧️ pride'), 'show pride');
      // 🏴‍☠️ = black flag + ZWJ + skull + crossbones + VS16.
      expect(stripEmojis('🏴‍☠️ pirate'), 'pirate');
    });

    test('strips subdivision flag tag sequences', () {
      // Scotland: 🏴 + tag chars (U+E0001-U+E007F) + cancel tag U+E007F.
      // Black-flag base is Extended_Pictographic; the cluster includes the
      // tag chars per UAX #29, so the whole subdivision flag drops as a unit.
      expect(stripEmojis('from 🏴󠁧󠁢󠁳󠁣󠁴󠁿 today'), 'from today');
      // England subdivision flag.
      expect(stripEmojis('🏴󠁧󠁢󠁥󠁮󠁧󠁿 cricket'), 'cricket');
    });

    test(
      'strips ©, ®, ™ (Extended_Pictographic, documents current behavior)',
      () {
        // ©, ®, ™ are technically Extended_Pictographic (Unicode 11+) and
        // render as emoji on some platforms. Our function strips them. If we
        // ever decide TTS should pronounce "copyright" / "trademark", we'll
        // need to narrow the property; this test pins the current behavior.
        expect(stripEmojis('Acme © 2026'), 'Acme 2026');
        expect(stripEmojis('Brand® new'), 'Brand new');
        expect(stripEmojis('Product™ ships'), 'Product ships');
        // Same chars with explicit emoji presentation (VS16), also stripped.
        expect(stripEmojis('Acme ©️ 2026'), 'Acme 2026');
      },
    );

    test('preserves bare digits without keycap', () {
      // No keycap mark → not emoji. Plain digits must survive.
      expect(stripEmojis('Year 2026 starts'), 'Year 2026 starts');
    });

    test('preserves # and * without keycap', () {
      expect(stripEmojis('use #tag and *bold*'), 'use #tag and *bold*');
    });

    test(
      'strips text-style symbols when followed by VS16 (emoji presentation)',
      () {
        // ✈ is Extended_Pictographic; with or without VS16 we should drop it.
        expect(stripEmojis('book ✈️ ticket'), 'book ticket');
        expect(stripEmojis('book ✈ ticket'), 'book ticket');
      },
    );

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

    test('collapses tab runs around stripped emoji', () {
      expect(stripEmojis('foo\t👋\tbar'), 'foo bar');
      expect(stripEmojis('a\t\t👋\t\tb'), 'a b');
    });

    test(
      'collapses NBSP and ideographic-space runs (ECMAScript whitespace)',
      () {
        // Dart RegExp \\s matches U+00A0 (NBSP) and U+3000 (ideographic space)
        // via ECMAScript whitespace semantics. After removing the emoji, runs
        // collapse to a single ASCII space.
        expect(stripEmojis('foo 👋 bar'), 'foo bar');
        expect(stripEmojis('日本　👋　語'), '日本 語');
      },
    );

    test('strips emoji adjacent to digits without affecting digit', () {
      // Common chat: "scored 100💯". 100 must survive; 💯 must drop.
      expect(stripEmojis('scored 100💯 today'), 'scored 100 today');
      expect(stripEmojis('💯100💯'), '100');
    });

    test('handles mixed RTL + LTR + emoji without mangling order', () {
      // Logical order is preserved (Dart strings are logical-order, not visual).
      // The emoji drops, surrounding bidi runs are untouched.
      expect(stripEmojis('Hello مرحبا 👋 world'), 'Hello مرحبا world');
      expect(stripEmojis('שלום world 🌍 again'), 'שלום world again');
    });

    test('preserves NFC and NFD forms of accented Latin equally', () {
      // NFC: c + a + f + é (single codepoint U+00E9).
      const nfc = 'café';
      // NFD: c + a + f + e + combining acute (U+0301).
      const nfd = 'café';
      expect(stripEmojis(nfc), nfc);
      expect(stripEmojis(nfd), nfd);
      expect(stripEmojis('$nfc 👋'), nfc);
      expect(stripEmojis('$nfd 👋'), nfd);
    });

    test('preserves lone ZWJ in non-emoji text', () {
      // ZWJ (U+200D) in non-emoji text formats Indic / Persian. Not in our
      // emoji-signal regex, so the cluster survives.
      const text = 'hello‍world';
      expect(stripEmojis(text), text);
    });

    test('preserves ZWNJ in Persian-style text', () {
      // ZWNJ (U+200C) prevents cursive joining: critical for Persian word
      // boundaries like می‌خواهم. Must survive.
      const persian = 'می‌خواهم';
      expect(stripEmojis(persian), persian);
      expect(stripEmojis('$persian 👋 today'), '$persian today');
    });

    test('preserves Hindi explicit-ZWJ conjunct', () {
      // Devanagari conjunct क्‍ष uses virama + ZWJ to force half-form.
      const hindi = 'क्‍ष';
      expect(stripEmojis(hindi), hindi);
    });

    test('preserves bidi formatting controls (LRM, RLM, isolates)', () {
      // U+200E LRM, U+200F RLM, U+2066-U+2069 (LRI/RLI/FSI/PDI). None are
      // Extended_Pictographic. Dropping them would mangle bidi rendering.
      expect(stripEmojis('a‎b‏c'), 'a‎b‏c');
      expect(
        stripEmojis('\u2066english\u2069 + \u2067arabic\u2069'),
        '\u2066english\u2069 + \u2067arabic\u2069',
      );
    });

    test('preserves polytonic Greek (Greek Extended block)', () {
      // U+1F00-U+1FFE in Plane 0. Not the Plane-1 emoji range that shares
      // some hex digits. Used in Ancient Greek / liturgical texts.
      expect(stripEmojis('Ἀθήνα 🏛️'), 'Ἀθήνα');
    });

    test('preserves superscript / ordinal indicators', () {
      // Spanish/Portuguese 1ª 1º, math x², chemistry H₂O. None are emoji.
      expect(stripEmojis('1ª y 1º 😀'), '1ª y 1º');
      expect(stripEmojis('H₂O and x² 🧪'), 'H₂O and x²');
    });

    test('preserves orphan variation selector (no emoji base)', () {
      // U+FE0F attaches to whatever grapheme precedes it. With a non-emoji
      // base, the cluster is not emoji and survives intact.
      const text = 'hello️world';
      expect(stripEmojis(text), text);
    });

    test('preserves Vietnamese decomposed tone marks', () {
      // NFC: t i ế (U+1EBF) n g. NFD: t i e + circumflex (U+0302) + acute
      // (U+0301) + n g. Both forms must survive.
      const nfc = 'tiếng';
      const nfd = 'tiếng';
      expect(stripEmojis(nfc), nfc);
      expect(stripEmojis(nfd), nfd);
    });

    test('preserves Thai stacked tone + vowel marks', () {
      // Thai uses combining vowel signs (U+0E34-U+0E37) and tone marks
      // (U+0E48-U+0E4B), often stacked. None are Extended_Pictographic.
      expect(stripEmojis('ภาษาไทย 🇹🇭'), 'ภาษาไทย');
    });

    test('preserves Hebrew niqqud (vowel points)', () {
      // Niqqud (U+05B0-U+05BD) and dagesh (U+05BC) are pointing marks,
      // not emoji. Must survive intact.
      const pointed = 'בְּרֵאשִׁית';
      expect(stripEmojis('$pointed 📖'), pointed);
    });

    test('preserves CJK supplementary-plane ideographs', () {
      // CJK Extension B (U+20000+) lives in the supplementary plane (4-byte
      // UTF-16). Not Extended_Pictographic. Must survive.
      const ext = '\u{20000}\u{2070E}';
      expect(stripEmojis('$ext 中文 👋'), '$ext 中文');
    });

    test('preserves Arabic kashida (tatweel)', () {
      // U+0640 visually elongates Arabic letters. Not emoji.
      expect(stripEmojis('سـلام 👋'), 'سـلام');
    });

    test('preserves Arabic presentation forms', () {
      // U+FB50-U+FDFF and U+FE70-U+FEFF hold pre-shaped Arabic glyphs that
      // appear in some serialized text. Not Extended_Pictographic.
      const presForm = 'ﻻﻷ'; // Lam-Alef ligatures.
      expect(stripEmojis('$presForm 👋'), presForm);
    });

    test('preserves U+FFFD replacement and other format chars', () {
      // U+FFFD (replacement) and U+FFFC (object replacement) appear in
      // pasted / corrupted text. Not Extended_Pictographic.
      expect(stripEmojis('lost � char 👋'), 'lost � char');
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

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/choreographer/igc/text_normalization_util.dart';

final List<Map<String, String>> normalizeTestCases = [
  // 1. Amharic (am) - beta
  {"input": "ሰላም!", "expected": "ሰላም"},
  {"input": "ተማሪ።", "expected": "ተማሪ"},
  {"input": "ኢትዮጵያ...", "expected": "ኢትዮጵያ"},

  // 2. Arabic (ar) - beta
  {"input": "السلام عليكم!", "expected": "السلام عليكم"},
  {"input": "مرحباً", "expected": "مرحباً"},
  {"input": "القاهرة.", "expected": "القاهرة"},
  {"input": "مدرسة؟", "expected": "مدرسة"},

  // 3. Bengali (bn) - beta
  {"input": "নমস্কার!", "expected": "নমস্কার"},
  {"input": "ভালো আছেন?", "expected": "ভালো আছেন"},
  {"input": "ঢাকা।", "expected": "ঢাকা"},

  // 4. Bulgarian (bg) - beta
  {"input": "Здравей!", "expected": "здравей"},
  {"input": "България", "expected": "българия"},
  {"input": "София.", "expected": "софия"},

  // 5. Catalan (ca) - full
  {"input": "Hola!", "expected": "hola"},
  {"input": "França", "expected": "franca"},
  {"input": "Barcelòna...", "expected": "barcelòna"},
  {"input": "això", "expected": "això"},

  // 6. Czech (cs) - beta
  {"input": "Dobrý den!", "expected": "dobry den"},
  {"input": "Děkuji", "expected": "dekuji"},
  {"input": "Praha.", "expected": "praha"},
  {"input": "škola?", "expected": "skola"},

  // 7. Danish (da) - beta
  {"input": "Hej!", "expected": "hej"},
  {"input": "København", "expected": "kobenhavn"},
  {"input": "Danskе.", "expected": "danske"},
  {"input": "æøå", "expected": "æøå"},

  // 8. German (de) - full
  {"input": "Guten Tag!", "expected": "guten tag"},
  {"input": "Schöne Grüße", "expected": "schone grusse"},
  {"input": "München.", "expected": "munchen"},
  {"input": "Straße?", "expected": "strasse"},
  {"input": "Hörst du mich?", "expected": "horst du mich"},

  // 9. Greek (el) - beta
  {"input": "Γεια σας!", "expected": "γεια σας"},
  {"input": "Αθήνα", "expected": "αθηνα"},
  {"input": "ελληνικά.", "expected": "ελληνικα"},

  // 10. English (en) - full
  {"input": "Hello world!", "expected": "hello world"},
  {"input": "It's a beautiful day.", "expected": "its a beautiful day"},
  {"input": "Don't worry, be happy!", "expected": "dont worry be happy"},
  {"input": "café", "expected": "cafe"},
  {"input": "résumé", "expected": "resume"},

  // 11. Spanish (es) - full
  {"input": "¡Hola mundo!", "expected": "hola mundo"},
  {"input": "Adiós", "expected": "adios"},
  {"input": "España.", "expected": "espana"},
  {"input": "niño", "expected": "nino"},
  {"input": "¿Cómo estás?", "expected": "como estas"},

  // 12. Estonian (et) - beta
  {"input": "Tere!", "expected": "tere"},
  {"input": "Tallinn", "expected": "tallinn"},
  {"input": "Eesti.", "expected": "eesti"},

  // 13. Basque (eu) - beta
  {"input": "Kaixo!", "expected": "kaixo"},
  {"input": "Euskera", "expected": "euskera"},
  {"input": "Bilbo.", "expected": "bilbo"},

  // 14. Finnish (fi) - beta
  {"input": "Hei!", "expected": "hei"},
  {"input": "Helsinki", "expected": "helsinki"},
  {"input": "Suomi.", "expected": "suomi"},
  {"input": "Käännös", "expected": "kaannos"},

  // 15. French (fr) - full
  {"input": "Bonjour!", "expected": "bonjour"},
  {"input": "À bientôt", "expected": "a bientot"},
  {"input": "Paris.", "expected": "paris"},
  {"input": "Français?", "expected": "francais"},
  {"input": "C'est magnifique!", "expected": "cest magnifique"},

  // 16. Galician (gl) - beta
  {"input": "Ola!", "expected": "ola"},
  {"input": "Galicia", "expected": "galicia"},
  {"input": "Santiago.", "expected": "santiago"},

  // 17. Gujarati (gu) - beta
  {"input": "નમસ્તે!", "expected": "નમસ્તે"},
  {"input": "ગુજરાત", "expected": "ગુજરાત"},
  {"input": "અમદાવાદ.", "expected": "અમદાવાદ"},

  // 18. Hindi (hi) - beta
  {"input": "नमस्ते!", "expected": "नमस्ते"},
  {"input": "भारत", "expected": "भारत"},
  {"input": "दिल्ली.", "expected": "दिल्ली"},
  {"input": "शिक्षा?", "expected": "शिक्षा"},

  // 19. Hungarian (hu) - beta
  {"input": "Szia!", "expected": "szia"},
  {"input": "Budapest", "expected": "budapest"},
  {"input": "Magyar.", "expected": "magyar"},
  {"input": "köszönöm", "expected": "koszonom"},

  // 20. Indonesian (id) - beta
  {"input": "Halo!", "expected": "halo"},
  {"input": "Jakarta", "expected": "jakarta"},
  {"input": "Indonesia.", "expected": "indonesia"},
  {"input": "selamat pagi", "expected": "selamat pagi"},

  // 21. Italian (it) - full
  {"input": "Ciao!", "expected": "ciao"},
  {"input": "Arrivederci", "expected": "arrivederci"},
  {"input": "Roma.", "expected": "roma"},
  {"input": "perché?", "expected": "perche"},
  {"input": "È bellissimo!", "expected": "e bellissimo"},

  // 22. Japanese (ja) - full
  {"input": "こんにちは！", "expected": "こんにちは"},
  {"input": "東京", "expected": "東京"},
  {"input": "ありがとう。", "expected": "ありがとう"},
  {"input": "さようなら？", "expected": "さようなら"},

  // 23. Kannada (kn) - beta
  {"input": "ನಮಸ್ತೆ!", "expected": "ನಮಸ್ತೆ"},
  {"input": "ಬೆಂಗಳೂರು", "expected": "ಬೆಂಗಳೂರು"},
  {"input": "ಕರ್ನಾಟಕ.", "expected": "ಕರ್ನಾಟಕ"},

  // 24. Korean (ko) - full
  {"input": "안녕하세요!", "expected": "안녕하세요"},
  {"input": "서울", "expected": "서울"},
  {"input": "한국어.", "expected": "한국어"},
  {"input": "감사합니다?", "expected": "감사합니다"},

  // 25. Lithuanian (lt) - beta
  {"input": "Labas!", "expected": "labas"},
  {"input": "Vilnius", "expected": "vilnius"},
  {"input": "Lietuva.", "expected": "lietuva"},
  {"input": "ačiū", "expected": "aciu"},

  // 26. Latvian (lv) - beta
  {"input": "Sveiki!", "expected": "sveiki"},
  {"input": "Rīga", "expected": "riga"},
  {"input": "Latvija.", "expected": "latvija"},

  // 27. Malay (ms) - beta
  {"input": "Selamat pagi!", "expected": "selamat pagi"},
  {"input": "Kuala Lumpur", "expected": "kuala lumpur"},
  {"input": "Malaysia.", "expected": "malaysia"},

  // 28. Mongolian (mn) - beta
  {"input": "Сайн байна уу!", "expected": "сайн байна уу"},
  {"input": "Улаанбаатар", "expected": "улаанбаатар"},
  {"input": "Монгол.", "expected": "монгол"},

  // 29. Marathi (mr) - beta
  {"input": "नमस्कार!", "expected": "नमस्कार"},
  {"input": "मुंबई", "expected": "मुंबई"},
  {"input": "महाराष्ट्र.", "expected": "महाराष्ट्र"},

  // 30. Dutch (nl) - beta
  {"input": "Hallo!", "expected": "hallo"},
  {"input": "Amsterdam", "expected": "amsterdam"},
  {"input": "Nederland.", "expected": "nederland"},
  {"input": "dankjewel", "expected": "dankjewel"},

  // 31. Punjabi (pa) - beta
  {"input": "ਸਤਿ ਸ਼੍ਰੀ ਅਕਾਲ!", "expected": "ਸਤਿ ਸ਼੍ਰੀ ਅਕਾਲ"},
  {"input": "ਪੰਜਾਬ", "expected": "ਪੰਜਾਬ"},
  {"input": "ਅੰਮ੍ਰਿਤਸਰ.", "expected": "ਅੰਮ੍ਰਿਤਸਰ"},

  // 32. Polish (pl) - beta
  {"input": "Cześć!", "expected": "czesc"},
  {"input": "Warszawa", "expected": "warszawa"},
  {"input": "Polska.", "expected": "polska"},
  {"input": "dziękuję", "expected": "dziekuje"},

  // 33. Portuguese (pt) - full
  {"input": "Olá!", "expected": "ola"},
  {"input": "Obrigado", "expected": "obrigado"},
  {"input": "São Paulo.", "expected": "sao paulo"},
  {"input": "coração", "expected": "coracao"},
  {"input": "não?", "expected": "nao"},

  // 34. Romanian (ro) - beta
  {"input": "Salut!", "expected": "salut"},
  {"input": "București", "expected": "bucuresti"},
  {"input": "România.", "expected": "romania"},
  {"input": "mulțumesc", "expected": "multumesc"},

  // 35. Russian (ru) - full
  {"input": "Привет!", "expected": "привет"},
  {"input": "Москва", "expected": "москва"},
  {"input": "Россия.", "expected": "россия"},
  {"input": "спасибо?", "expected": "спасибо"},
  {"input": "магазин", "expected": "магазин"},
  {"input": "магазин.", "expected": "магазин"},

  // 36. Slovak (sk) - beta
  {"input": "Ahoj!", "expected": "ahoj"},
  {"input": "Bratislava", "expected": "bratislava"},
  {"input": "Slovensko.", "expected": "slovensko"},
  {"input": "ďakujem", "expected": "dakujem"},

  // 37. Serbian (sr) - beta
  {"input": "Здраво!", "expected": "здраво"},
  {"input": "Београд", "expected": "београд"},
  {"input": "Србија.", "expected": "србија"},

  // 38. Ukrainian (uk) - beta
  {"input": "Привіт!", "expected": "привіт"},
  {"input": "Київ", "expected": "київ"},
  {"input": "Україна.", "expected": "україна"},

  // 39. Urdu (ur) - beta
  {"input": "السلام علیکم!", "expected": "السلام علیکم"},
  {"input": "کراچی", "expected": "کراچی"},
  {"input": "پاکستان.", "expected": "پاکستان"},

  // 40. Vietnamese (vi) - full
  {"input": "Xin chào!", "expected": "xin chao"},
  {"input": "Hà Nội", "expected": "ha noi"},
  {"input": "Việt Nam.", "expected": "viet nam"},
  {"input": "cảm ơn?", "expected": "cam on"},

  // 41. Cantonese (yue) - beta
  {"input": "你好！", "expected": "你好"},
  {"input": "香港", "expected": "香港"},
  {"input": "廣東話.", "expected": "廣東話"},

  // 42. Chinese Simplified (zh-CN) - full
  {"input": "你好！", "expected": "你好"},
  {"input": "北京", "expected": "北京"},
  {"input": "中国.", "expected": "中国"},
  {"input": "谢谢?", "expected": "谢谢"},

  // 43. Chinese Traditional (zh-TW) - full
  {"input": "您好！", "expected": "您好"},
  {"input": "台北", "expected": "台北"},
  {"input": "台灣.", "expected": "台灣"},

  // Edge cases and special scenarios

  // Mixed script and punctuation
  {"input": "Hello世界!", "expected": "hello世界"},
  {"input": "café-restaurant", "expected": "cafe restaurant"},

  // Multiple spaces and whitespace normalization
  {"input": "   hello    world   ", "expected": "hello world"},
  {"input": "test\t\n  text", "expected": "test text"},

  // Numbers and alphanumeric
  {"input": "test123!", "expected": "test123"},
  {"input": "COVID-19", "expected": "covid 19"},
  {"input": "2023年", "expected": "2023年"},

  // Empty and whitespace only
  {"input": "", "expected": ""},
  {"input": "   ", "expected": ""},
  {"input": "!!!", "expected": ""},

  // Special punctuation combinations
  {"input": "What?!?", "expected": "what"},
  {"input": "Well...", "expected": "well"},
  {"input": "Hi---there", "expected": "hi there"},

  // Diacritics and accents across languages
  {"input": "café résumé naïve", "expected": "cafe resume naive"},
  {"input": "piñata jalapeño", "expected": "pinata jalapeno"},
  {"input": "Zürich Müller", "expected": "zurich muller"},
  {"input": "François Böhm", "expected": "francois bohm"},

  // Currency and symbols
  {"input": "\$100 €50 ¥1000", "expected": "100 50 1000"},
  {"input": "@username #hashtag", "expected": "username hashtag"},
  {"input": "50% off!", "expected": "50 off"},

  // Quotation marks and brackets
  {"input": "\"Hello\"", "expected": "hello"},
  {"input": "(test)", "expected": "test"},
  {"input": "[important]", "expected": "important"},
  {"input": "{data}", "expected": "data"},

  // Apostrophes and contractions
  {"input": "don't can't won't", "expected": "dont cant wont"},
  {"input": "it's they're we've", "expected": "its theyre weve"},

  // Hyphenated words
  {"input": "twenty-one", "expected": "twenty one"},
  {"input": "state-of-the-art", "expected": "state of the art"},
  {"input": "re-enter", "expected": "re enter"},
];

// Helper function to run all normalization tests
void runNormalizationTests() {
  int passed = 0;
  final int total = normalizeTestCases.length;

  for (int i = 0; i < normalizeTestCases.length; i++) {
    final testCase = normalizeTestCases[i];
    final input = testCase['input']!;
    final expected = testCase['expected']!;
    final actual = normalizeString(input, 'en'); // Default to English for tests

    if (actual == expected) {
      passed++;
      Logs().i('✓ Test ${i + 1} PASSED: "$input" → "$actual"');
    } else {
      Logs().i(
        '✗ Test ${i + 1} FAILED: "$input" → "$actual" (expected: "$expected")',
      );
    }
  }

  Logs().i(
    '\nTest Results: $passed/$total tests passed (${(passed / total * 100).toStringAsFixed(1)}%)',
  );
}

// Main function to run the tests when executed directly
// flutter test lib/pangea/choreographer/utils/normalize_text.dart
void main() {
  group('Normalize String Tests', () {
    for (int i = 0; i < normalizeTestCases.length; i++) {
      final testCase = normalizeTestCases[i];
      final input = testCase['input']!;
      final expected = testCase['expected']!;

      test('Test ${i + 1}: "$input" should normalize to "$expected"', () {
        final actual =
            normalizeString(input, 'en'); // Default to English for tests
        expect(
          actual,
          equals(expected),
          reason: 'Input: "$input" → Got: "$actual" → Expected: "$expected"',
        );
      });
    }
  });
}

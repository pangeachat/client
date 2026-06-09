import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/choreographer/igc/text_normalization_util.dart';

final List<Map<String, String>> normalizeTestCases = [
  // 1. Amharic (am) - beta
  {"input": "ሰላም!", "expected": "ሰላም", "language": "am"},
  {"input": "ተማሪ።", "expected": "ተማሪ", "language": "am"},
  {"input": "ኢትዮጵያ...", "expected": "ኢትዮጵያ", "language": "am"},

  // 2. Arabic (ar) - beta
  {"input": "السلام عليكم!", "expected": "السلام عليكم", "language": "ar"},
  {"input": "مرحباً", "expected": "مرحباً", "language": "ar"},
  {"input": "القاهرة.", "expected": "القاهرة", "language": "ar"},
  {"input": "مدرسة؟", "expected": "مدرسة", "language": "ar"},

  // 3. Bengali (bn) - beta
  {"input": "নমস্কার!", "expected": "নমস্কার", "language": "bn"},
  {"input": "ভালো আছেন?", "expected": "ভালো আছেন", "language": "bn"},
  {"input": "ঢাকা।", "expected": "ঢাকা", "language": "bn"},

  // 4. Bulgarian (bg) - beta
  {"input": "Здравей!", "expected": "здравей", "language": "bg"},
  {"input": "България", "expected": "българия", "language": "bg"},
  {"input": "София.", "expected": "софия", "language": "bg"},

  // 5. Catalan (ca) - full
  {"input": "Hola!", "expected": "hola", "language": "ca"},
  {"input": "França", "expected": "frança", "language": "ca"},
  {"input": "Barcelòna...", "expected": "barcelòna", "language": "ca"},
  {"input": "això", "expected": "això", "language": "ca"},

  // 6. Czech (cs) - beta
  {"input": "Dobrý den!", "expected": "dobry den", "language": "cs"},
  {"input": "Děkuji", "expected": "dekuji", "language": "cs"},
  {"input": "Praha.", "expected": "praha", "language": "cs"},
  {"input": "škola?", "expected": "skola", "language": "cs"},

  // 7. Danish (da) - beta
  {"input": "Hej!", "expected": "hej", "language": "da"},
  {"input": "København", "expected": "københavn", "language": "da"},
  {"input": "Danske.", "expected": "danske", "language": "da"},
  {"input": "æøå", "expected": "æøå", "language": "da"},

  // 8. German (de) - full
  {"input": "Guten Tag!", "expected": "guten tag", "language": "de"},
  {"input": "Schöne Grüße", "expected": "schone grusse", "language": "de"},
  {"input": "München.", "expected": "munchen", "language": "de"},
  {"input": "Straße?", "expected": "strasse", "language": "de"},
  {"input": "Hörst du mich?", "expected": "horst du mich", "language": "de"},

  // 9. Greek (el) - beta
  {"input": "Γεια σας!", "expected": "γεια σας", "language": "el"},
  {"input": "Αθήνα", "expected": "αθηνα", "language": "el"},
  {"input": "ελληνικά.", "expected": "ελληνικα", "language": "el"},

  // 10. English (en) - full
  {"input": "Hello world!", "expected": "hello world", "language": "en"},
  {
    "input": "It's a beautiful day.",
    "expected": "its a beautiful day",
    "language": "en",
  },
  {
    "input": "Don't worry, be happy!",
    "expected": "dont worry be happy",
    "language": "en",
  },
  {"input": "café", "expected": "cafe", "language": "en"},
  {"input": "résumé", "expected": "resume", "language": "en"},

  // 11. Spanish (es) - full
  {"input": "¡Hola mundo!", "expected": "hola mundo", "language": "es"},
  {"input": "Adiós", "expected": "adios", "language": "es"},
  {"input": "España.", "expected": "espana", "language": "es"},
  {"input": "niño", "expected": "nino", "language": "es"},
  {"input": "¿Cómo estás?", "expected": "como estas", "language": "es"},

  // 12. Estonian (et) - beta
  {"input": "Tere!", "expected": "tere", "language": "et"},
  {"input": "Tallinn", "expected": "tallinn", "language": "et"},
  {"input": "Eesti.", "expected": "eesti", "language": "et"},

  // 13. Basque (eu) - beta
  {"input": "Kaixo!", "expected": "kaixo", "language": "eu"},
  {"input": "Euskera", "expected": "euskera", "language": "eu"},
  {"input": "Bilbo.", "expected": "bilbo", "language": "eu"},

  // 14. Finnish (fi) - beta
  {"input": "Hei!", "expected": "hei", "language": "fi"},
  {"input": "Helsinki", "expected": "helsinki", "language": "fi"},
  {"input": "Suomi.", "expected": "suomi", "language": "fi"},
  {"input": "Käännös", "expected": "kaannos", "language": "fi"},

  // 15. French (fr) - full
  {"input": "Bonjour!", "expected": "bonjour", "language": "fr"},
  {"input": "À bientôt", "expected": "a bientot", "language": "fr"},
  {"input": "Paris.", "expected": "paris", "language": "fr"},
  {"input": "Français?", "expected": "francais", "language": "fr"},
  {
    "input": "C'est magnifique!",
    "expected": "cest magnifique",
    "language": "fr",
  },

  // 16. Galician (gl) - beta
  {"input": "Ola!", "expected": "ola", "language": "gl"},
  {"input": "Galicia", "expected": "galicia", "language": "gl"},
  {"input": "Santiago.", "expected": "santiago", "language": "gl"},

  // 17. Gujarati (gu) - beta
  {"input": "નમસ્તે!", "expected": "નમસ્તે", "language": "gu"},
  {"input": "ગુજરાત", "expected": "ગુજરાત", "language": "gu"},
  {"input": "અમદાવાદ.", "expected": "અમદાવાદ", "language": "gu"},

  // 18. Hindi (hi) - beta
  {"input": "नमस्ते!", "expected": "नमस्ते", "language": "hi"},
  {"input": "भारत", "expected": "भारत", "language": "hi"},
  {"input": "दिल्ली.", "expected": "दिल्ली", "language": "hi"},
  {"input": "शिक्षा?", "expected": "शिक्षा", "language": "hi"},

  // 19. Hungarian (hu) - beta
  {"input": "Szia!", "expected": "szia", "language": "hu"},
  {"input": "Budapest", "expected": "budapest", "language": "hu"},
  {"input": "Magyar.", "expected": "magyar", "language": "hu"},
  {"input": "köszönöm", "expected": "koszonom", "language": "hu"},

  // 20. Indonesian (id) - beta
  {"input": "Halo!", "expected": "halo", "language": "id"},
  {"input": "Jakarta", "expected": "jakarta", "language": "id"},
  {"input": "Indonesia.", "expected": "indonesia", "language": "id"},
  {"input": "selamat pagi", "expected": "selamat pagi", "language": "id"},

  // 21. Italian (it) - full
  {"input": "Ciao!", "expected": "ciao", "language": "it"},
  {"input": "Arrivederci", "expected": "arrivederci", "language": "it"},
  {"input": "Roma.", "expected": "roma", "language": "it"},
  {"input": "perché?", "expected": "perche", "language": "it"},
  {"input": "È bellissimo!", "expected": "e bellissimo", "language": "it"},

  // 22. Japanese (ja) - full
  {"input": "こんにちは！", "expected": "こんにちは", "language": "ja"},
  {"input": "東京", "expected": "東京", "language": "ja"},
  {"input": "ありがとう。", "expected": "ありがとう", "language": "ja"},
  {"input": "さようなら？", "expected": "さようなら", "language": "ja"},

  // 23. Kannada (kn) - beta
  {"input": "ನಮಸ್ತೆ!", "expected": "ನಮಸ್ತೆ", "language": "kn"},
  {"input": "ಬೆಂಗಳೂರು", "expected": "ಬೆಂಗಳೂರು", "language": "kn"},
  {"input": "ಕರ್ನಾಟಕ.", "expected": "ಕರ್ನಾಟಕ", "language": "kn"},

  // 24. Korean (ko) - full
  {"input": "안녕하세요!", "expected": "안녕하세요", "language": "ko"},
  {"input": "서울", "expected": "서울", "language": "ko"},
  {"input": "한국어.", "expected": "한국어", "language": "ko"},
  {"input": "감사합니다?", "expected": "감사합니다", "language": "ko"},

  // 25. Lithuanian (lt) - beta
  {"input": "Labas!", "expected": "labas", "language": "lt"},
  {"input": "Vilnius", "expected": "vilnius", "language": "lt"},
  {"input": "Lietuva.", "expected": "lietuva", "language": "lt"},
  {"input": "ačiū", "expected": "aciu", "language": "lt"},

  // 26. Latvian (lt) - beta
  {"input": "Sveiki!", "expected": "sveiki", "language": "lt"},
  {"input": "Rīga", "expected": "riga", "language": "lt"},
  {"input": "Latvija.", "expected": "latvija", "language": "lt"},

  // 27. Malay (ms) - beta
  {"input": "Selamat pagi!", "expected": "selamat pagi", "language": "ms"},
  {"input": "Kuala Lumpur", "expected": "kuala lumpur", "language": "ms"},
  {"input": "Malaysia.", "expected": "malaysia", "language": "ms"},

  // 28. Mongolian (mn) - beta
  {"input": "Сайн байна уу!", "expected": "сайн байна уу", "language": "mn"},
  {"input": "Улаанбаатар", "expected": "улаанбаатар", "language": "mn"},
  {"input": "Монгол.", "expected": "монгол", "language": "mn"},

  // 29. Marathi (mr) - beta
  {"input": "नमस्कार!", "expected": "नमस्कार", "language": "mr"},
  {"input": "मुंबई", "expected": "मुंबई", "language": "mr"},
  {"input": "महाराष्ट्र.", "expected": "महाराष्ट्र", "language": "mr"},

  // 30. Dutch (nl) - beta
  {"input": "Hallo!", "expected": "hallo", "language": "nl"},
  {"input": "Amsterdam", "expected": "amsterdam", "language": "nl"},
  {"input": "Nederland.", "expected": "nederland", "language": "nl"},
  {"input": "dankjewel", "expected": "dankjewel", "language": "nl"},

  // 31. Punjabi (pa) - beta
  {"input": "ਸਤਿ ਸ਼੍ਰੀ ਅਕਾਲ!", "expected": "ਸਤਿ ਸ਼੍ਰੀ ਅਕਾਲ", "language": "pa"},
  {"input": "ਪੰਜਾਬ", "expected": "ਪੰਜਾਬ", "language": "pa"},
  {"input": "ਅੰਮ੍ਰਿਤਸਰ.", "expected": "ਅੰਮ੍ਰਿਤਸਰ", "language": "pa"},

  // 32. Polish (pl) - beta
  {"input": "Cześć!", "expected": "czesc", "language": "pl"},
  {"input": "Warszawa", "expected": "warszawa", "language": "pl"},
  {"input": "Polska.", "expected": "polska", "language": "pl"},
  {"input": "dziękuję", "expected": "dziekuje", "language": "pl"},

  // 33. Portuguese (pt) - full
  {"input": "Olá!", "expected": "ola", "language": "pt"},
  {"input": "Obrigado", "expected": "obrigado", "language": "pt"},
  {"input": "São Paulo.", "expected": "sao paulo", "language": "pt"},
  {"input": "coração", "expected": "coracao", "language": "pt"},
  {"input": "não?", "expected": "nao", "language": "pt"},

  // 34. Romanian (ro) - beta
  {"input": "Salut!", "expected": "salut", "language": "ro"},
  {"input": "București", "expected": "bucuresti", "language": "ro"},
  {"input": "România.", "expected": "romania", "language": "ro"},
  {"input": "mulțumesc", "expected": "multumesc", "language": "ro"},

  // 35. Russian (ru) - full
  {"input": "Привет!", "expected": "привет", "language": "ru"},
  {"input": "Москва", "expected": "москва", "language": "ru"},
  {"input": "Россия.", "expected": "россия", "language": "ru"},
  {"input": "спасибо?", "expected": "спасибо", "language": "ru"},
  {"input": "магазин", "expected": "магазин", "language": "ru"},
  {"input": "магазин.", "expected": "магазин", "language": "ru"},

  // 36. Slovak (sk) - beta
  {"input": "Ahoj!", "expected": "ahoj", "language": "sk"},
  {"input": "Bratislava", "expected": "bratislava", "language": "sk"},
  {"input": "Slovensko.", "expected": "slovensko", "language": "sk"},
  {"input": "ďakujem", "expected": "dakujem", "language": "sk"},

  // 37. Serbian (sr) - beta
  {"input": "Здраво!", "expected": "здраво", "language": "sr"},
  {"input": "Београд", "expected": "београд", "language": "sr"},
  {"input": "Србија.", "expected": "србија", "language": "sr"},

  // 38. Ukrainian (uk) - beta
  {"input": "Привіт!", "expected": "привіт", "language": "uk"},
  {"input": "Київ", "expected": "київ", "language": "uk"},
  {"input": "Україна.", "expected": "україна", "language": "uk"},

  // 39. Urdu (ur) - beta
  {"input": "السلام علیکم!", "expected": "السلام علیکم", "language": "ur"},
  {"input": "کراچی", "expected": "کراچی", "language": "ur"},
  {"input": "پاکستان.", "expected": "پاکستان", "language": "ur"},

  // 40. Vietnamese (vi) - full
  {"input": "Xin chào!", "expected": "xin chao", "language": "vi"},
  {"input": "Hà Nội", "expected": "ha noi", "language": "vi"},
  {"input": "Việt Nam.", "expected": "viet nam", "language": "vi"},
  {"input": "cảm ơn?", "expected": "cam on", "language": "vi"},

  // 41. Cantonese (yue) - beta
  {"input": "你好！", "expected": "你好", "language": "yue"},
  {"input": "香港", "expected": "香港", "language": "yue"},
  {"input": "廣東話.", "expected": "廣東話", "language": "yue"},

  // 42. Chinese Simplified (zh-CN) - full
  {"input": "你好！", "expected": "你好", "language": "zh-CN"},
  {"input": "北京", "expected": "北京", "language": "zh-CN"},
  {"input": "中国.", "expected": "中国", "language": "zh-CN"},
  {"input": "谢谢?", "expected": "谢谢", "language": "zh-CN"},

  // 43. Chinese Traditional (zh-TW) - full
  {"input": "您好！", "expected": "您好", "language": "zh-TW"},
  {"input": "台北", "expected": "台北", "language": "zh-TW"},
  {"input": "台灣.", "expected": "台灣", "language": "zh-TW"},

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
      final language = testCase['language'] ?? 'en';
      final expected = testCase['expected']!;

      test('Test ${i + 1}: "$input" should normalize to "$expected"', () {
        final actual = normalizeString(
          input,
          language,
        ); // Default to English for tests
        expect(
          actual,
          equals(expected),
          reason: 'Input: "$input" → Got: "$actual" → Expected: "$expected"',
        );
      });
    }
  });
}

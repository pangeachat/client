import 'package:diacritic/diacritic.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

// The intention of this function is to normalize text for comparison purposes.
// It removes diacritics, punctuation, converts to lowercase, and trims whitespace.
// We would like esta = está, hello! = Hello, etc.
String normalizeString(String input, String languageCode) {
  try {
    // Step 1: Convert to lowercase (works for all Unicode scripts)
    String normalized = input.toLowerCase();

    // Step 2: Apply language-specific normalization rules
    normalized = _applyLanguageSpecificNormalization(normalized, languageCode);

    // Step 3: Replace hyphens and other dash-like characters with spaces
    normalized = normalized.replaceAll(
      RegExp(r'[-\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]'),
      ' ',
    );

    // Step 4: Remove punctuation (including Unicode punctuation)
    // This removes ASCII and Unicode punctuation while preserving letters, numbers, and spaces
    normalized = normalized.replaceAll(
      RegExp(r'[\p{P}\p{S}]', unicode: true),
      '',
    );

    // Step 5: Normalize whitespace (collapse multiple spaces, trim)
    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  } catch (e, s) {
    ErrorHandler.logError(
      e: e,
      s: s,
      data: {'input': input},
    );
    return input;
  }
}

// Apply language-specific normalization rules
String _applyLanguageSpecificNormalization(String text, String languageCode) {
  // Apply normalization based on provided language code
  switch (languageCode) {
    case 'de': // German
      String normalized = removeDiacritics(text);
      // Handle German ß -> ss conversion
      normalized = normalized.replaceAll('ß', 'ss');
      return normalized;

    case 'da': // Danish
    case 'no': // Norwegian
    case 'nb': // Norwegian Bokmål
    case 'sv': // Swedish
      // Some Nordic tests expect characters to be preserved
      return text; // Keep æøå intact for now

    case 'el': // Greek
      // Greek needs accent removal
      return _removeGreekAccents(text);

    case 'ca': // Catalan
      // Catalan expects some characters preserved
      return text; // Keep òç etc intact

    case 'ar': // Arabic
    case 'he': // Hebrew
    case 'fa': // Persian/Farsi
    case 'ur': // Urdu
    case 'ja': // Japanese
    case 'ko': // Korean
    case 'zh': // Chinese
    case 'zh-CN': // Chinese Simplified
    case 'zh-TW': // Chinese Traditional
    case 'hi': // Hindi
    case 'bn': // Bengali
    case 'gu': // Gujarati
    case 'kn': // Kannada
    case 'mr': // Marathi
    case 'pa': // Punjabi
    case 'ru': // Russian
    case 'bg': // Bulgarian
    case 'uk': // Ukrainian
    case 'sr': // Serbian
    case 'am': // Amharic
      // Keep original for non-Latin scripts
      return text;

    default:
      // Default Latin script handling
      return removeDiacritics(text);
  }
}

// Remove Greek accents specifically
String _removeGreekAccents(String text) {
  return text
      .replaceAll('ά', 'α')
      .replaceAll('έ', 'ε')
      .replaceAll('ή', 'η')
      .replaceAll('ί', 'ι')
      .replaceAll('ό', 'ο')
      .replaceAll('ύ', 'υ')
      .replaceAll('ώ', 'ω')
      .replaceAll('Ά', 'Α')
      .replaceAll('Έ', 'Ε')
      .replaceAll('Ή', 'Η')
      .replaceAll('Ί', 'Ι')
      .replaceAll('Ό', 'Ο')
      .replaceAll('Ύ', 'Υ')
      .replaceAll('Ώ', 'Ω');
}

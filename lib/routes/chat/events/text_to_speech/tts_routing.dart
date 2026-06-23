import 'package:collection/collection.dart';

/// Result of choosing the best device voice for a language.
///
/// [voice] is the `{name, locale}` to pass to `flutter_tts.setVoice`, or null
/// when the device offers no voice for the language. [isKnownGood] means the
/// voice clears the quality bar so we can skip backend TTS. [hasVoice] is false
/// only when there is no device voice at all.
class TtsVoiceSelection {
  final Map<String, String>? voice;
  final bool isKnownGood;
  final bool hasVoice;

  const TtsVoiceSelection({
    required this.voice,
    required this.isKnownGood,
    required this.hasVoice,
  });
}

/// Pure device-vs-backend routing logic for word-level TTS, with no dependency
/// on `flutter_tts`, the network, or app state, so it is unit-testable.
///
/// See client/.github/instructions/word-text-to-speech.instructions.md for the
/// design (known-good-voice gate, web name patterns, native quality field).
class TtsRouting {
  /// Web-only: voice-name markers that reliably indicate a high-quality voice.
  /// flutter_tts surfaces only the name on web (it drops `quality`,
  /// `localService`, and `voiceURI`), so the name is the sole signal. Broad
  /// vendor conventions, matched case-insensitively as substrings.
  static const List<String> webGoodVoiceNamePatterns = [
    'google', // Chrome network voices, e.g. "Google Deutsch"
    'online (natural)', // Edge neural voices
    '(enhanced)', // downloaded Apple voices
    '(premium)',
  ];

  /// Web-only: specific voice names to never treat as good even if they match a
  /// pattern above. Empty for now; add field-reported bad voices here.
  static const List<String> webExcludedVoiceNames = [];

  /// Native quality rank at/above which a device voice is "known-good" and we
  /// skip backend. iOS `enhanced`/`premium` and Android `high`/`very high`.
  static const int nativeGoodQualityRank = 4;

  /// Pick the best device voice for [langCode] from [voices] (the shape returned
  /// by `flutter_tts.getVoices`). [isWeb] selects the signal: name patterns on
  /// web, the `quality` field on native.
  static TtsVoiceSelection selectVoice(
    List<Map<String, String>> voices,
    String langCode, {
    required bool isWeb,
  }) {
    final target = langCode.toLowerCase();
    final short = target.split('-').first;
    final candidates = voices.where((v) {
      final loc = (v['locale'] ?? '').toLowerCase();
      return loc == target || (short.isNotEmpty && loc.startsWith(short));
    }).toList();

    if (candidates.isEmpty) {
      return const TtsVoiceSelection(
        voice: null,
        isKnownGood: false,
        hasVoice: false,
      );
    }

    Map<String, String> key(Map<String, String> v) => {
      'name': v['name'] ?? '',
      'locale': v['locale'] ?? '',
    };

    if (isWeb) {
      final good = candidates.firstWhereOrNull(
        (v) => isGoodWebVoiceName(v['name'] ?? ''),
      );
      return TtsVoiceSelection(
        voice: key(good ?? candidates.first),
        isKnownGood: good != null,
        hasVoice: true,
      );
    }

    candidates.sort(
      (a, b) => qualityRank(b['quality']).compareTo(qualityRank(a['quality'])),
    );
    final best = candidates.first;
    return TtsVoiceSelection(
      voice: key(best),
      isKnownGood: qualityRank(best['quality']) >= nativeGoodQualityRank,
      hasVoice: true,
    );
  }

  /// Whether the request should go to backend TTS rather than the device.
  ///
  /// A phoneme override needs backend (device can't render phonemes); otherwise
  /// the device is used when it offers a known-good voice. Backend TTS is
  /// Pro-only, so unsubscribed users always stay on device regardless.
  static bool useBackend({
    required bool hasPhoneme,
    required TtsVoiceSelection selection,
    required bool isSubscribed,
  }) {
    if (hasPhoneme) return isSubscribed;
    if (!selection.hasVoice) return isSubscribed;
    if (selection.isKnownGood) return false;
    return isSubscribed;
  }

  static bool isGoodWebVoiceName(String name) {
    final lower = name.toLowerCase();
    if (webExcludedVoiceNames.any((n) => n.toLowerCase() == lower)) {
      return false;
    }
    return webGoodVoiceNamePatterns.any(lower.contains);
  }

  static int qualityRank(String? quality) {
    switch ((quality ?? '').toLowerCase()) {
      case 'premium': // iOS
      case 'very high': // Android
        return 5;
      case 'enhanced': // iOS
      case 'high': // Android
        return 4;
      case 'normal': // Android
        return 3;
      case 'default': // iOS
        return 2;
      case 'low': // Android
        return 1;
      case 'very low': // Android
        return 0;
      default:
        return 2;
    }
  }
}

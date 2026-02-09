import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_models.dart';

/// Disambiguation result for choosing which pronunciation(s) to display.
class DisambiguationResult {
  /// The matched pronunciation, or null if zero or multiple matches.
  final Pronunciation? matched;

  /// All pronunciations (for fallback display).
  final List<Pronunciation> all;

  const DisambiguationResult({this.matched, required this.all});

  bool get isAmbiguous => matched == null && all.length > 1;
  bool get isUnambiguous => all.length == 1 || matched != null;

  /// The transcription to display (single match or slash-separated fallback).
  String get displayTranscription {
    if (matched != null) return matched!.transcription;
    if (all.length == 1) return all.first.transcription;
    return all.map((p) => p.transcription).join(' / ');
  }

  /// The IPA for TTS. Returns the matched IPA, or null if ambiguous
  /// (caller should let user choose or use the first).
  String? get ipa {
    if (matched != null) return matched!.ipa;
    if (all.length == 1) return all.first.ipa;
    return null;
  }
}

/// Disambiguate pronunciations against available UD context.
///
/// [pos] — POS tag from PangeaToken (uppercase, e.g. "VERB").
/// [morph] — morphological features from PangeaToken (e.g. {"Tense": "Past"}).
///
/// Both may be null (analytics page has limited context).
DisambiguationResult disambiguate(
  List<Pronunciation> pronunciations, {
  String? pos,
  Map<String, String>? morph,
}) {
  if (pronunciations.isEmpty) {
    return const DisambiguationResult(all: []);
  }
  if (pronunciations.length == 1) {
    return DisambiguationResult(
      matched: pronunciations.first,
      all: pronunciations,
    );
  }

  // Try to find a pronunciation whose ud_conditions all match.
  final matches = pronunciations.where((p) {
    if (p.udConditions == null) return true; // unconditional = always matches
    return _matchesConditions(p.udConditions!, pos: pos, morph: morph);
  }).toList();

  if (matches.length == 1) {
    return DisambiguationResult(matched: matches.first, all: pronunciations);
  }

  // Ambiguous — return all.
  return DisambiguationResult(all: pronunciations);
}

/// Parse ud_conditions string and check if all conditions are met.
///
/// Format: "Pos=ADV;Tense=Past" — semicolon-separated feature=value pairs.
/// "Pos" is matched against [pos] (case-insensitive).
/// Other features are matched against [morph].
bool _matchesConditions(
  String udConditions, {
  String? pos,
  Map<String, String>? morph,
}) {
  final conditions = udConditions.split(';');
  for (final cond in conditions) {
    final parts = cond.split('=');
    if (parts.length != 2) continue;

    final feature = parts[0].trim();
    final value = parts[1].trim();

    if (feature.toLowerCase() == 'pos') {
      if (pos == null) return false;
      if (pos.toLowerCase() != value.toLowerCase()) return false;
    } else {
      if (morph == null) return false;
      // UD features use PascalCase keys. Match case-insensitively
      // in case the morph map uses different casing.
      final morphValue =
          morph.entries.where((e) => e.key.toLowerCase() == feature.toLowerCase()).map((e) => e.value).firstOrNull;
      if (morphValue == null) return false;
      if (morphValue.toLowerCase() != value.toLowerCase()) return false;
    }
  }
  return true;
}

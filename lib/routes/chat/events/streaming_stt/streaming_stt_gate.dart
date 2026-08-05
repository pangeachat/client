/// The flag + language gate for streaming STT (D5/D11).
///
/// Streaming activates only when [Environment.liveStreamingSttEnabled] is ON
/// AND the message language is in the blessed streaming set. Otherwise today's
/// batch record-then-transcribe path runs unchanged. Kept as a pure function so
/// the decision is unit-testable without touching dotenv / storage.
abstract final class StreamingSttGate {
  /// The blessed streaming languages (short codes). This literal is FINALIZED to be byte-equal to
  /// the generated T6a pack
  /// (`test/pangea/streaming_stt/streaming_supported_langs/supported_streaming_languages.json`) —
  /// the single cross-repo source of truth; `supported_langs_contract_test.dart` FAILS if the two
  /// diverge (D5), and the T9 `cmp` gate (M14) enforces byte-identity with choreo. Widen ONLY by
  /// regenerating the pack from the choreo table and re-pinning this literal in the same change.
  static const Set<String> supportedLangCodesShort = <String>{
    // 'de' is an OWNER OVERRIDE (choreo OWNER_OVERRIDE_LANGUAGES): German failed the W3
    // eval (Soniox returned empty on ~1/10 clips) but is routed to Soniox anyway; an empty
    // stream degrades to the batch chain. Byte-equal to the choreo pack (contract test).
    'de',
    'en',
    'es',
    'fr',
    'it',
    'pt',
  };

  /// Canonicalize a message language to a stable table key (H7/KD-13):
  /// lowercase, strip region, and fold the Chinese family to 'zh' like the
  /// server. [applies] separately decides whether that key is currently routed.
  ///
  /// PUBLIC because the connect factory must send the same canonical language
  /// the gate matched into the relay `?lang=` query. Chinese aliases currently
  /// canonicalize to the batch-only 'zh' key and therefore never reach the
  /// factory. Returns null for an empty/absent code.
  static String? canonicalShort(String? code) {
    if (code == null) return null;
    final base = code.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    if (base.isEmpty) return null;
    return (base == 'cmn' || base == 'yue') ? 'zh' : base;
  }

  /// True when the streaming capture path should be taken for a message in
  /// [messageLangCodeShort], given whether the feature flag is [flagEnabled].
  static bool applies({
    required bool flagEnabled,
    required String? messageLangCodeShort,
  }) {
    if (!flagEnabled) return false;
    final canon = canonicalShort(messageLangCodeShort);
    if (canon == null) return false;
    return supportedLangCodesShort.contains(canon);
  }

  /// True for the ONE case that warrants the D11 "not available for this
  /// language yet" degradation banner: the pilot is ON and [messageLangCodeShort]
  /// is a KNOWN language that is specifically NOT in the routed streaming set.
  ///
  /// Deliberately false for a null/unknown language: an unresolved target (L2
  /// not loaded yet) is not a language failure, so it must not be mislabeled as
  /// unsupported — it stays silent, the same outcome as a flag-off session.
  static bool languageUnsupported({
    required bool flagEnabled,
    required String? messageLangCodeShort,
  }) {
    if (!flagEnabled) return false;
    if (canonicalShort(messageLangCodeShort) == null) return false;
    return !applies(
      flagEnabled: flagEnabled,
      messageLangCodeShort: messageLangCodeShort,
    );
  }
}

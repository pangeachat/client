/// The product's name for one thing a learner can do in the language, the
/// unit every activity satisfies and every star counts (org glossary: Can-Do).
///
/// Kept in English in every locale on purpose, so it is a constant rather
/// than an l10n key. Teachers know the term from the NCSSFL-ACTFL Can-Do
/// Statements, Japan's education ministry uses "CAN-DO" untranslated, and
/// only German has a natural noun for it; machine-translating a coined noun
/// into every locale would name the same thing differently from one language
/// to the next. A string that puts other words around the term keeps those
/// words in l10n and takes the term as a placeholder (`{canDo}`, `{canDos}`).
/// See localization.instructions.md, "Terms kept in English".
abstract final class CanDoTerm {
  static const String singular = 'Can-Do';
  static const String plural = 'Can-Dos';
}

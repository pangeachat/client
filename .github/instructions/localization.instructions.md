---
applyTo: "lib/l10n/**,scripts/translate/**"
description: "Client UI localization — the arb model, the L1-coverage principle, and the Vertex-Gemini translation + dead-key tooling."
---

# Localization — Client

How the Flutter client's UI strings are stored, translated, and kept in sync. For the cross-service language list and what makes a language an L1, see [language-list.instructions.md](../../../.github/.github/instructions/language-list.instructions.md).

## The arb model

- UI strings live in `lib/l10n/intl_<locale>.arb` (JSON). `intl_en.arb` is the **template** and the source of truth for keys and ICU structure.
- `flutter gen-l10n` generates the `L10n` Dart classes from the arb files and writes untranslated keys per locale to `needed-translations.txt`.
- **Only the template carries `@`-metadata** (placeholder types, plural definitions). Locale files hold just `@@locale`, `@@last_modified`, and the translated key→value strings — gen-l10n reads placeholder metadata from the template.
- Locale selection falls back to English for any key (or whole locale) not translated, so a missing translation degrades gracefully rather than breaking the UI.

## L1 coverage principle

Every L1 — every language in the CMS `languages` collection — should get a UI translation. A language is offered as an L1 only if an LLM we route to supports it (the L1 gate in the language-list doc), so offering it while showing English UI is the mismatch we're closing. Until a locale is translated it falls back to English; the backfill tooling below exists to drive that gap to zero.

## Translation tooling

- **[`translate_gemini.py`](../../scripts/translate/translate_gemini.py)** translates one locale from `intl_en.arb` with **Gemini on Vertex AI** — 2.5 Flash by default (fast, thinking off; the right call for bulk backfill of short UI strings), or `--model gemini-2.5-pro` when a locale warrants higher quality. It is the canonical translator (it replaced the legacy OpenAI / DeepL scripts).
  - **ICU safety is a hard gate.** Placeholders (`{count}`) and plural/select syntax must survive verbatim — the model is instructed to preserve them, and every value is then validated (placeholder set matches English, plural/select structure intact). The script **refuses to write** an arb if any value fails. AI-translated locales are recorded in `ai-translated-keys.json` so native-speaker corrections can layer on later.
  - **Vertex, not AI Studio.** Auth is the service account / ADC on the org's Cloud Billing. The AI Studio API-key path is deprecated — its prepaid credit pool depletes silently.
- **[`backfill_l10n.py`](../../scripts/translate/backfill_l10n.py)** fetches the L1 list from the CMS, diffs it against existing locales, and runs the translator for every missing one in parallel. Resumable (skips existing locales); one language failing doesn't abort the batch.

Always run `flutter gen-l10n` after translating, and commit the regenerated locale set.

## Dead-key hygiene

`intl_en.arb` inherits FluffyChat base keys the product doesn't use. [`find_unused_intl_keys.py`](../../scripts/find_unused_intl_keys.py) lists keys unreferenced anywhere in the code (git-grep), and [`remove_unused_intl_keys.py`](../../scripts/remove_unused_intl_keys.py) strips them from every locale. Trim before backfilling so dead copy isn't translated into every locale. Serialize with `ensure_ascii=False` (raw UTF-8) to match the existing files — escaping Unicode rewrites every non-Latin locale wholesale.

## Keeping copy in sync

When `intl_en.arb` changes, every locale falls behind. `gen-l10n` surfaces the gap in `needed-translations.txt`; re-run the translator to close it. A CI guard that fails when a PR leaves `needed-translations.txt` non-empty is the intended backstop against drift.

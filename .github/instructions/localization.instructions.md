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

## Which language the app UI uses

By default the app UI is shown in the user's **source/native language (L1)**. A learner can opt into **immersion** — showing the UI in their **target language (L2)** — via the `appLanguageIsTarget` flag in `UserSettings` (toggle on the learning settings page). [`MatrixState._setAppLanguage`](../../lib/widgets/matrix.dart) resolves the locale from that flag, falling back to L1 (then system) when L2 isn't set. Because it's a non-language setting, the change propagates on `settingsUpdateStream`, which `_setAppLanguage` also listens to so the toggle takes effect immediately. Untranslated L2 keys fall back to English like any other locale.

## L1 coverage principle

Every L1 — every language in the CMS `languages` collection — should get a UI translation. A language is offered as an L1 only if an LLM we route to supports it (the L1 gate in the language-list doc), so offering it while showing English UI is the mismatch we're closing. Until a locale is translated it falls back to English; the backfill tooling below exists to drive that gap to zero.

## Translation tooling

**Running the scripts is self-contained — no choreo env, no venv.** Each script
declares its own dependencies inline (PEP 723), so the canonical invocation is
`uv run scripts/translate/<script>.py ...` from the client repo. The only
other prerequisite is Google auth: `gcloud auth application-default login`.
Vertex billing defaults to the `pangea-chat-dev-llm` project (user accounts
typically lack Vertex perms on whatever project ADC happens to default to);
`VERTEX_PROJECT` overrides.

- **[`translate_gemini.py`](../../scripts/translate/translate_gemini.py)** translates one locale from `intl_en.arb` with **Gemini on Vertex AI** — 2.5 Flash by default (fast, thinking off; the right call for bulk backfill of short UI strings), or `--model gemini-2.5-pro` when a locale warrants higher quality. It is the canonical translator (it replaced the legacy OpenAI / DeepL scripts).
  - **ICU safety is a hard gate.** Placeholders (`{count}`) and plural/select syntax must survive verbatim — the model is instructed to preserve them, and every value is then validated (placeholder set matches English, plural/select structure intact). The script **refuses to write** an arb if any value fails. AI-translated locales are recorded in `ai-translated-keys.json` so native-speaker corrections can layer on later.
  - **Vertex, not AI Studio.** Auth is the service account / ADC on the org's Cloud Billing. The AI Studio API-key path is deprecated — its prepaid credit pool depletes silently.
- **[`backfill_l10n.py`](../../scripts/translate/backfill_l10n.py)** fetches the L1 list from the CMS, diffs it against existing locales, and runs the translator for every missing one in parallel. Resumable (skips existing locales); one language failing doesn't abort the batch.
- **[`translate_new_keys.py`](../../scripts/translate/translate_new_keys.py)** fills newly-added template keys into every EXISTING locale — the l10n-sync gate's remediation path when a PR adds keys to `intl_en.arb`. It translates only each locale's missing keys and merges them in, never touching existing values (so native-speaker corrections survive), with the same ICU refuse-to-write gate and `ai-translated-keys.json` provenance.
- **[`audit_fix_translations.py`](../../scripts/translate/audit_fix_translations.py)** reviews an *existing* locale against English with Gemini 2.5 Pro and proposes fixes for mistranslations, untranslated strings, and broken placeholders — keeping correct copy verbatim. **Review-assisted, not blind-apply**: an LLM reviewer has a persistent bias toward restyling even when told not to. Run it with `--dry`, have a human vet the proposed diff, and apply selectively — do not auto-run it across community (human-translated) locales.

Always run `flutter gen-l10n` after translating, then spot-check a few locales against English — especially non-Latin scripts and plural/placeholder keys — and commit the arb files plus `ai-translated-keys.json`. Prompt language names resolve from the CMS `languages` collection (the cross-service language SOT — its `language_name` and ISO 15924 `script` fields disambiguate `zh` Simplified vs `zh_Hant` Traditional, `pt_BR` vs `pt_PT`): a bare name like "Chinese" once yielded Traditional characters for `zh`. `resolve_display_name` in `translate_gemini.py` matches the arb code's script subtag against the CMS entries, using the Unicode CLDR likely-script (bare `zh` → Hans) for base-code arbs, and falls back to unambiguous BCP-47 tags when the CMS is unreachable. Spot-checking script-variant locales stays worthwhile as the backstop. Provenance lists in `ai-translated-keys.json` are written **sorted** per locale, so a future key adds one line; a one-time reorder-only diff there is expected, not corruption.

## Dead-key hygiene

`intl_en.arb` inherits FluffyChat base keys the product doesn't use. [`find_unused_intl_keys.py`](../../scripts/find_unused_intl_keys.py) lists keys unreferenced anywhere in the code (git-grep), and [`remove_unused_intl_keys.py`](../../scripts/remove_unused_intl_keys.py) strips them from every locale. Trim before backfilling so dead copy isn't translated into every locale. Serialize with `ensure_ascii=False` (raw UTF-8) to match the existing files — escaping Unicode rewrites every non-Latin locale wholesale.

## Keeping copy in sync

When `intl_en.arb` changes, every locale falls behind — and `gen-l10n` only catches *added* keys (missing from a locale), never *updated* ones (a key whose English value changed while the stale translation stays present).

[`check_l10n_sync.py`](../../scripts/translate/check_l10n_sync.py) closes both gaps. On a PR it diffs `intl_en.arb` against the base branch and splits what changed into two tiers, run by the [`l10n_sync_check`](../../.github/workflows/l10n_sync_check.yaml) workflow:

- **Added keys → blocking.** A newly-added English key that isn't translated into every locale ships English-only (the gap that let the immersion toggle merge untranslated). Any locale missing an added key **fails the check** — run `uv run scripts/translate/translate_new_keys.py`, then `flutter gen-l10n`, and commit before merging.
- **Value-changed keys → warning.** When an existing key's English text changes but a locale keeps its old translation, the locale still renders (just slightly stale), so this only **warns** — a copy tweak isn't blocked on re-translating every locale.

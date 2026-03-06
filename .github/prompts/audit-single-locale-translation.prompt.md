# Audit Single Locale Translation

Audit one specific locale ARB file against the English template and produce a language-focused report with actionable fixes.

## Goal

Given a target locale file (for example `lib/l10n/intl_es.arb`), detect translation quality and schema issues relative to `lib/l10n/intl_en.arb`.

## Inputs

- `targetLocaleFile`: path to locale file under `lib/l10n/` (must match `intl_*.arb`, must not be `intl_en.arb`)
- English template: `lib/l10n/intl_en.arb`

## Setup

1. Ensure `.workspace/translation-key-audit/` exists.
2. Create a locale-specific output folder:
   - `.workspace/translation-key-audit/single-locale/<locale-code>/`
   - Example: `.workspace/translation-key-audit/single-locale/es/`

## Audit checks

### 1) Structural key diff

Compare non-metadata keys (`!startsWith('@')`) between English and target locale:

- **Missing keys**: in English but absent in target locale
- **Orphaned keys**: in target locale but absent in English

### 2) Metadata consistency

For each shared key, compare metadata object shape where present:

- Placeholder names
- Placeholder count
- Placeholder type mismatches
- Missing metadata object in target when English defines one (or vice versa)

### 3) Placeholder usage correctness

For keys with placeholders in English:

- Ensure each placeholder token appears in target string (`{name}` format)
- Flag missing placeholders in target string
- Flag extra placeholders in target string not defined by English metadata

### 4) Value quality checks

Flag likely-problematic values in target locale:

- Empty or whitespace-only strings
- Exact copy of English for long phrases (possible untranslated text)
- Suspiciously short values for long English source (heuristic)

Do not auto-fix in this prompt; report only.

## Required outputs

Write all files under `.workspace/translation-key-audit/single-locale/<locale-code>/`:

### `summary.md`

Include:

- Locale file audited
- Total key counts (English/target/shared)
- Missing key count
- Orphaned key count
- Placeholder mismatch count
- Value-quality flag count
- Priority action list

### `missing-keys.txt`

One key per line.

### `orphaned-keys.txt`

One key per line.

### `placeholder-mismatches.md`

Per-key details:

- Expected placeholders (English)
- Observed placeholders (target metadata and target string)
- Exact mismatch reason

### `value-quality-flags.md`

Per-key details for empty/untranslated/suspicious values.

### `recommended-patches.md`

Patch recommendations only (no applied changes):

- Key
- Suggested target value/source of truth
- Reason category (`missing`, `orphaned`, `placeholder_mismatch`, `quality`)
- Risk note

## Guardrails

- Do not write outside `.workspace/translation-key-audit/`.
- Do not modify tracked locale files in this prompt.
- Keep outputs deterministic and reproducible.
- If `targetLocaleFile` is invalid or missing, fail with a clear error and stop.

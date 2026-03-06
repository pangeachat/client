# Detect Unused English Translation Keys

Detect unused translation keys in the Flutter client English template and produce reproducible audit artifacts.

## Goal

Given `lib/l10n/intl_en.arb`, determine which English keys are still referenced in non-generated Dart source and which are stale candidates for removal.

## Scope

- Source of truth: `lib/l10n/intl_en.arb`
- Code search scope: `lib/**/*.dart`
- Exclude generated localization sources: `lib/l10n/*.dart`
- Exclude tests and build outputs

## Setup

1. Ensure `.workspace/translation-key-audit/` exists.
2. Write all outputs only under `.workspace/translation-key-audit/`.

## Procedure

### 1) Collect English keys

- Parse `lib/l10n/intl_en.arb` as JSON.
- Collect all non-metadata keys (exclude keys beginning with `@` or `@@`).

### 2) Detect key usage in Dart source

For each English key, classify usage based on identifier presence in non-generated `.dart` files.

Treat as usage when key appears in localization access patterns, including:

- `L10n.of(context).keyName`
- `L10n.of(context)!.keyName`
- `l10n.keyName`
- `AppLocalizations.of(context).keyName`

If no usage is found, mark as `unused`.

### 3) Determine likely origin

- `pangea` if all usage paths are under `lib/pangea/`
- `fluffychat` if all usage paths are outside `lib/pangea/`
- `mixed` if both appear
- `unknown` if unused

### 4) Cross-locale consistency checks

Using `lib/l10n/intl_*.arb` excluding `intl_en.arb`, report:

- English keys missing in many locale files (translation gaps)
- Keys present in non-English locale files but missing from English (orphaned)
- Keys referenced in code but absent from English template

## Required outputs

### `.workspace/translation-key-audit/key-inventory.md`

Markdown table:

| Key Name | Status | Used In (files) | Origin | Notes |
|----------|--------|-----------------|--------|-------|

Status must be one of: `active`, `unused`, `unknown`.

### `.workspace/translation-key-audit/findings.md`

Include:

- Total key count in English
- Active/unused/unknown counts
- Action items (unused key removal candidates)
- Translation gaps summary
- Orphaned keys summary
- Code-referenced keys missing from English

### `.workspace/translation-key-audit/unused-keys.txt`

One unused key per line.

### `.workspace/translation-key-audit/raw-search-results.md`

Reproducible raw per-key evidence (or explicit `No matches`).

## Guardrails

- Do not edit tracked source files as part of this audit prompt.
- Do not write outputs outside `.workspace/translation-key-audit/`.
- Keep outputs deterministic and re-runnable.

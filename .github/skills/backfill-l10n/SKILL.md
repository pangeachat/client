---
name: backfill-l10n
description: Use when adding or refreshing client UI translations — backfilling `.arb` locales for languages that lack one, translating a single new locale, or re-translating after `intl_en.arb` changes. Runs the Vertex-Gemini translator with the ICU-preservation validation gate.
---

# Backfill / refresh client UI translations

**MUST READ [localization.instructions.md](../../instructions/localization.instructions.md) first** — it owns the arb model, the L1-coverage principle, the ICU-safety gate, and why we use Vertex (not AI Studio).

## Prereqs

- Python deps: `google-genai`, `google-auth` (in the choreo venv, or `pip install`).
- **Vertex auth** (Cloud Billing, not the deprecated AI Studio key):
  - `GOOGLE_APPLICATION_CREDENTIALS` → a cloud-platform-scoped service-account JSON (or `gcloud auth application-default login`).
  - Optional `VERTEX_PROJECT` (default: the SA's own project), `VERTEX_LOCATION` (default `global`).
- Flutter on PATH for `flutter gen-l10n`.

## Run it

Backfill every L1 language that lacks a translation (parallel, resumable):

```sh
python scripts/translate/backfill_l10n.py --workers 10
```

Translate or refresh a single locale:

```sh
python scripts/translate/translate_gemini.py --lang sw --name Swahili
# smoke test first: add --limit 40 --dry
```

## After translating (required)

```sh
flutter gen-l10n                      # regenerate L10n Dart + needed-translations.txt
python -c "import json,glob; [json.load(open(f)) for f in glob.glob('lib/l10n/intl_*.arb')]"  # arb still valid JSON
```

Then spot-check a few locales (especially non-Latin scripts) — read the plural/placeholder keys against English — and commit the arb files plus `ai-translated-keys.json`. The translator refuses to write a locale whose ICU/placeholders don't match English, so a written arb has already passed structural validation.

## Trim dead keys before a large backfill

```sh
python scripts/find_unused_intl_keys.py && python scripts/remove_unused_intl_keys.py
```

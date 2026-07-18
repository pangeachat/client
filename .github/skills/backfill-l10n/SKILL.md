---
name: backfill-l10n
description: Use when adding or refreshing client UI translations — filling newly-added `intl_en.arb` keys into existing locales (the l10n-sync CI gate's remediation), backfilling `.arb` locales for languages that lack one, or re-translating a single locale. Runs the Vertex-Gemini translator with the ICU-preservation validation gate.
---

# Backfill / refresh client UI translations

**MUST READ [localization.instructions.md](../../instructions/localization.instructions.md) first** — it owns the arb model, the tooling design (per-script roles, self-contained `uv run` deps, Vertex auth and project), the ICU-safety gate, and the post-run checks (spot-check guidance, the `zh` Simplified trap, provenance).

## Pick the right script

| Situation | Command |
| --- | --- |
| A PR added key(s) to `intl_en.arb`; the **l10n-sync gate** is failing | `uv run scripts/translate/translate_new_keys.py` (optionally `--keys keyA keyB`; `--dry` first on big batches) |
| A language has **no `intl_<lang>.arb` at all** (new L1s) | `uv run scripts/translate/backfill_l10n.py --workers 10` |
| Translate or fully re-translate **one locale** | `uv run scripts/translate/translate_gemini.py --lang sw --name Swahili` (smoke test: `--limit 40 --dry`) |

Prereq: `gcloud auth application-default login` once per ~week (tokens expire).

## After translating (required)

```sh
flutter gen-l10n                                                 # regenerate L10n Dart
uv run scripts/translate/check_l10n_sync.py --base origin/main   # the CI gate, locally
```

Spot-check and commit per the doc's post-run checks, including `ai-translated-keys.json`.

## Trim dead keys before a large backfill

```sh
python scripts/find_unused_intl_keys.py && python scripts/remove_unused_intl_keys.py
```

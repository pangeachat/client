"""Translate newly-added template keys into every EXISTING locale arb.

The l10n-sync CI gate blocks a PR that adds keys to `intl_en.arb` until every
locale carries them. `translate_gemini.py` rewrites a whole locale (clobbering
native-speaker corrections) and `backfill_l10n.py` only creates missing
locales — this script fills the third case: translate ONLY the keys each
existing locale is missing and merge them in, leaving every existing value
untouched.

Design: client/.github/instructions/localization.instructions.md.

Prereqs: Vertex auth as documented in translate_gemini.py. Run
`flutter gen-l10n` afterwards to regenerate the Dart localizations.

Usage:
  uv run scripts/translate/translate_new_keys.py [--keys endPractice ...]
      [--workers 10] [--dry] [--cms-url <url>]

With no --keys, fills every template key a locale is missing.
"""

# /// script
# requires-python = ">=3.11"
# dependencies = ["google-genai>=1.0", "google-auth"]
# ///

import argparse
import concurrent.futures
import glob
import json
import os
from datetime import datetime
from pathlib import Path

from translate_gemini import (
    CMS_LANGUAGES_URL,
    fetch_cms_languages,
    resolve_display_name,
    translate_batch,
    validate,
    vertex_client,
)

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
L10N = REPO / "lib" / "l10n"
BATCH = 80


def locale_paths() -> list:
    return sorted(
        p
        for p in glob.glob(str(L10N / "intl_*.arb"))
        if not p.endswith("intl_en.arb")
    )


def fill_locale(
    client, model: str, path: Path, en: dict, only: set | None, docs: list, dry: bool
) -> tuple[str, str, list[str]]:
    """Returns (message, locale code, keys added). Only writes the locale's own
    arb — the shared provenance file is written once by main() after all
    workers finish (a per-worker read-modify-write raced)."""
    code = path.name[len("intl_") : -len(".arb")]
    doc = json.loads(path.read_text(encoding="utf-8"))
    template_keys = [k for k in en if not k.startswith("@")]
    missing = [k for k in template_keys if k not in doc]
    if only is not None:
        missing = [k for k in missing if k in only]
    if not missing:
        return f"skip {code} (complete)", code, []

    name = resolve_display_name(code, docs)
    out: dict[str, str] = {}
    errors: list[str] = []
    for i in range(0, len(missing), BATCH):
        chunk = missing[i : i + BATCH]
        tr = translate_batch(client, model, name, {k: en[k] for k in chunk})
        for k in chunk:
            if k not in tr:
                errors.append(f"{k}: MISSING from response")
                continue
            err = validate(en[k], tr[k])
            if err:
                errors.append(f"{k}: {err} | en={en[k]!r} tr={tr[k]!r}")
            out[k] = tr[k]

    if errors:
        # Same contract as translate_gemini: never write a locale that failed
        # ICU validation.
        return f"FAIL {code}: " + "; ".join(errors[:3]), code, []
    if dry:
        return f"dry {code}: would add {len(out)} key(s)", code, []

    doc.update(out)
    doc["@@last_modified"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
    path.write_text(
        json.dumps(doc, indent=4, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return f"OK {code}: added {len(out)} key(s)", code, sorted(out)


def record_provenance(added: dict[str, list[str]]) -> None:
    if not added:
        return
    prov_path = L10N / "ai-translated-keys.json"
    prov = (
        json.loads(prov_path.read_text(encoding="utf-8"))
        if prov_path.exists()
        else {}
    )
    for code, keys in added.items():
        prov[code] = sorted(set(prov.get(code, [])) | set(keys))
    prov_path.write_text(
        json.dumps(prov, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keys", nargs="*", help="only fill these keys (default: all missing)")
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--dry", action="store_true", help="translate + validate, don't write")
    ap.add_argument("--cms-url", default=CMS_LANGUAGES_URL)
    ap.add_argument(
        "--model", default="gemini-2.5-flash",
        help="Gemini model (default gemini-2.5-flash)",
    )
    args = ap.parse_args()

    en = json.loads((L10N / "intl_en.arb").read_text(encoding="utf-8"))
    only = set(args.keys) if args.keys else None
    if only:
        unknown = only - set(en)
        if unknown:
            raise SystemExit(f"keys not in intl_en.arb: {sorted(unknown)}")

    docs = fetch_cms_languages(args.cms_url)
    client = vertex_client()

    paths = [Path(p) for p in locale_paths()]
    failures = 0
    added: dict[str, list[str]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {
            ex.submit(fill_locale, client, args.model, p, en, only, docs, args.dry): p
            for p in paths
        }
        for fut in concurrent.futures.as_completed(futs):
            try:
                msg, code, keys = fut.result()
                if keys:
                    added[code] = keys
            except Exception as e:
                msg = f"FAIL {futs[fut].name}: {type(e).__name__} {e}"
            if msg.startswith("FAIL"):
                failures += 1
            if not msg.startswith("skip"):
                print(msg)

    record_provenance(added)
    if failures:
        raise SystemExit(f"{failures} locale(s) failed — their arbs were not written; rerun (it resumes) after fixing")
    print("done — run `flutter gen-l10n` to regenerate Dart localizations")


if __name__ == "__main__":
    main()

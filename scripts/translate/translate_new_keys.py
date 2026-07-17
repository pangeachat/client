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
  python scripts/translate/translate_new_keys.py [--keys endPractice ...]
      [--workers 10] [--dry] [--cms-url <url>]

With no --keys, fills every template key a locale is missing.
"""

import argparse
import concurrent.futures
import glob
import json
import os
import urllib.request
from datetime import datetime
from pathlib import Path

from translate_gemini import translate_batch, validate, vertex_client

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
L10N = REPO / "lib" / "l10n"
DEFAULT_CMS = "https://api.staging.pangea.chat/cms/api/languages?limit=500"
BATCH = 80


def cms_names(cms_url: str) -> dict:
    try:
        docs = json.load(urllib.request.urlopen(cms_url, timeout=30))["docs"]
    except Exception as e:  # names are prompt sugar only — never fatal
        print(f"CMS name fetch failed ({e}); using ISO codes in prompts")
        return {}
    names = {}
    for d in docs:
        base = d["language_code"].split("-")[0]
        name = (d.get("language_name") or "").strip()
        if name:
            names.setdefault(base, name)
    return names


def display_name(code: str, names: dict) -> str:
    base = code.split("-")[0].split("_")[0]
    return names.get(base) or f"the language with ISO 639 code '{code}'"


def locale_paths() -> list:
    return sorted(
        p
        for p in glob.glob(str(L10N / "intl_*.arb"))
        if not p.endswith("intl_en.arb")
    )


def fill_locale(
    client, model: str, path: Path, en: dict, only: set | None, names: dict, dry: bool
) -> str:
    code = path.name[len("intl_") : -len(".arb")]
    doc = json.loads(path.read_text(encoding="utf-8"))
    template_keys = [k for k in en if not k.startswith("@")]
    missing = [k for k in template_keys if k not in doc]
    if only is not None:
        missing = [k for k in missing if k in only]
    if not missing:
        return f"skip {code} (complete)"

    name = display_name(code, names)
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
        return f"FAIL {code}: " + "; ".join(errors[:3])
    if dry:
        return f"dry {code}: would add {len(out)} key(s)"

    doc.update(out)
    doc["@@last_modified"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
    path.write_text(
        json.dumps(doc, indent=4, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    prov_path = L10N / "ai-translated-keys.json"
    prov = (
        json.loads(prov_path.read_text(encoding="utf-8"))
        if prov_path.exists()
        else {}
    )
    prov[code] = sorted(set(prov.get(code, [])) | set(out))
    prov_path.write_text(
        json.dumps(prov, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )
    return f"OK {code}: added {len(out)} key(s)"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keys", nargs="*", help="only fill these keys (default: all missing)")
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--dry", action="store_true", help="translate + validate, don't write")
    ap.add_argument("--cms-url", default=DEFAULT_CMS)
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

    names = cms_names(args.cms_url)
    client = vertex_client()

    paths = [Path(p) for p in locale_paths()]
    failures = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {
            ex.submit(fill_locale, client, args.model, p, en, only, names, args.dry): p
            for p in paths
        }
        for fut in concurrent.futures.as_completed(futs):
            try:
                msg = fut.result()
            except Exception as e:
                msg = f"FAIL {futs[fut].name}: {type(e).__name__} {e}"
            if msg.startswith("FAIL"):
                failures += 1
            if not msg.startswith("skip"):
                print(msg)

    if failures:
        raise SystemExit(f"{failures} locale(s) failed — nothing written for them; rerun after fixing")
    print("done — run `flutter gen-l10n` to regenerate Dart localizations")


if __name__ == "__main__":
    main()

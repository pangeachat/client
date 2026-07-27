"""Backfill UI translations for every L1 language that lacks an `intl_<lang>.arb`.

Fetches the L1 language list from the CMS (the cross-service source of truth —
every language there is LLM-supported, so it belongs as an L1), diffs it against
the existing arb locales, and runs `translate_gemini.py` for each missing one,
several in parallel. Resumable (skips locales that already exist) and tolerant
of a single language failing (logged, not fatal).

Design: client/.github/instructions/localization.instructions.md.

Prereqs: Vertex auth as documented in translate_gemini.py. Run `flutter gen-l10n`
afterwards to regenerate the Dart localizations.

Usage:
  uv run scripts/translate/backfill_l10n.py [--workers 10] [--cms-url <url>]
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
import subprocess
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
L10N = REPO / "lib" / "l10n"
DEFAULT_CMS = "https://api.staging.pangea.chat/cms/api/languages?limit=500"


def existing_locale_bases() -> set:
    return {
        os.path.basename(p)[len("intl_"):-len(".arb")].split("-")[0].split("_")[0]
        for p in glob.glob(str(L10N / "intl_*.arb"))
    }


def missing_l1s(cms_url: str) -> list:
    docs = json.load(urllib.request.urlopen(cms_url, timeout=30))["docs"]
    have = existing_locale_bases()
    seen, rows = set(), []
    for d in docs:
        code = d["language_code"]
        if "-" in code:  # translate by base locale, not regional variant
            continue
        base = code.split("-")[0]
        if base in have or base in seen:
            continue
        seen.add(base)
        rows.append((code, d.get("language_name", "").strip()))
    return sorted(rows)


def run_one(cn: tuple) -> str:
    code, name = cn
    if (L10N / f"intl_{code}.arb").exists():
        return f"skip {code}"
    r = subprocess.run(
        [sys.executable, str(HERE / "translate_gemini.py"),
         "--lang", code, "--name", name, "--l10n", str(L10N)],
        capture_output=True, text=True,
    )
    (HERE / f".backfill_{code}.log").write_text(r.stdout + r.stderr)
    return f"{'OK' if r.returncode == 0 else 'FAIL'} {code} ({name})"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--cms-url", default=DEFAULT_CMS)
    args = ap.parse_args()

    langs = missing_l1s(args.cms_url)
    print(f"{len(langs)} L1 languages missing a UI translation")
    done, failed = 0, []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for result in ex.map(run_one, langs):
            done += 1
            print(f"[{done}/{len(langs)}] {result}", flush=True)
            if result.startswith("FAIL"):
                failed.append(result)
    print(f"\n=== done. {len(failed)} failures ===")
    for f in failed:
        print(" ", f)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()

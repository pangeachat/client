"""CI check: notify when English UI copy changes without translations catching up.

Compares `intl_en.arb` against a base git ref. Any key added or whose English
value changed is stale in every locale that wasn't also updated for it in the
same change. Emits GitHub Actions warning annotations listing the stale locales
so the PR author can re-translate (scripts/translate/translate_gemini.py or the
backfill-l10n skill). Notify-only — it does not fail the build.

Usage (CI): python scripts/translate/check_l10n_sync.py --base origin/main
"""

import argparse
import glob
import json
import os
import subprocess
import sys


def git_show_json(ref: str, path: str) -> dict:
    r = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return {}
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return {}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--l10n", default="lib/l10n")
    args = ap.parse_args()

    en_now = json.load(open(f"{args.l10n}/intl_en.arb", encoding="utf-8"))
    en_base = git_show_json(args.base, f"{args.l10n}/intl_en.arb")
    keys = [k for k in en_now if not k.startswith("@")]
    added = [k for k in keys if k not in en_base]
    value_changed = [k for k in keys if k in en_base and en_now[k] != en_base[k]]

    if not added and not value_changed:
        print("l10n sync: no English UI copy changed in this PR.")
        return

    # Two tiers. ADDED keys are new copy that ships English-only until every
    # locale has them — this is the gap that lets a feature merge untranslated,
    # so a locale missing an added key BLOCKS. VALUE-CHANGED keys only WARN: the
    # existing translation still renders (just slightly stale), so a copy tweak
    # isn't blocked on re-translating every locale.
    untranslated: dict[str, list[str]] = {}  # added keys missing from a locale -> block
    stale: dict[str, list[str]] = {}  # changed keys the locale didn't update -> warn
    for p in sorted(glob.glob(f"{args.l10n}/intl_*.arb")):
        loc = os.path.basename(p)[len("intl_"):-len(".arb")]
        if loc == "en":
            continue
        now = json.load(open(p, encoding="utf-8"))
        base = git_show_json(args.base, p)
        u = [k for k in added if k not in now]
        s = [k for k in value_changed if now.get(k) == base.get(k)]
        if u:
            untranslated[loc] = u
        if s:
            stale[loc] = s

    if added:
        print(f"{len(added)} English key(s) added: {sorted(added)}")
    if value_changed:
        print(f"{len(value_changed)} English key(s) value-changed: {sorted(value_changed)}")

    if stale:
        pairs = sum(len(v) for v in stale.values())
        print(
            f"::warning title=Translations may be stale::{len(stale)} locale(s) still hold "
            f"the previous translation for {len(value_changed)} changed key(s) ({pairs} pairs). "
            f"Consider re-translating with scripts/translate/translate_gemini.py."
        )

    if untranslated:
        pairs = sum(len(v) for v in untranslated.values())
        print(
            f"::error title=New strings are untranslated::{len(untranslated)} locale(s) are "
            f"missing {len(added)} newly-added key(s) ({pairs} pairs). Translate them "
            f"(`uv run scripts/translate/translate_new_keys.py`) and "
            f"commit before merging."
        )
        for loc, ks in sorted(untranslated.items())[:20]:
            print(f"  {loc}: missing {len(ks)}")
        sys.exit(1)

    print("New keys are translated across all locales. In sync.")


if __name__ == "__main__":
    main()

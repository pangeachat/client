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
    changed = [k for k in keys if en_now[k] != en_base.get(k)]  # added or value-changed

    if not changed:
        print("l10n sync: no English UI copy changed in this PR.")
        return

    stale: dict[str, list[str]] = {}
    for p in sorted(glob.glob(f"{args.l10n}/intl_*.arb")):
        loc = os.path.basename(p)[len("intl_"):-len(".arb")]
        if loc == "en":
            continue
        now = json.load(open(p, encoding="utf-8"))
        base = git_show_json(args.base, p)
        # stale = English changed but this locale's value for the key did not
        s = [k for k in changed if now.get(k) == base.get(k)]
        if s:
            stale[loc] = s

    print(f"{len(changed)} English key(s) changed or added: {sorted(changed)}")
    if not stale:
        print("All locales were updated for these keys — translations in sync.")
        return

    total = sum(len(v) for v in stale.values())
    print(
        f"::warning title=Translations out of sync::{len(stale)} locale(s) are stale "
        f"for {len(changed)} changed English key(s) ({total} locale-key pairs). "
        f"Re-translate with scripts/translate/translate_gemini.py or the backfill-l10n skill."
    )
    for loc, ks in sorted(stale.items()):
        print(f"  {loc}: {len(ks)} key(s) not updated")


if __name__ == "__main__":
    main()

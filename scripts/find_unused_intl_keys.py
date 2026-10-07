#!/usr/bin/env python3
"""
Find translation keys in intl_en.arb that no Dart code references.

A key counts as referenced when its name appears as an identifier on a line of
tracked Dart code outside lib/l10n/ (where the generated L10n class lives) that
is not a `//` comment line. gen-l10n keys are only reachable from Dart, so a
reported key has no reader. The match errs towards "referenced": a dead key
that shares its name with another identifier (`restricted`, also an enum
value) or a word in a trailing comment is not reported. e2e specs also read
keys out of intl_en.arb, but e2e/check-locator-keys.js already fails CI when a
spec's key has no widget.

Usage:
    python3 scripts/find_unused_intl_keys.py

Output:
    scripts/unused_intl_keys.json - the unused keys, read by remove_unused_intl_keys.py
"""

import json
import re
import subprocess
import sys

from arb_file import REPO_ROOT, TEMPLATE_ARB, translation_keys

OUTPUT_PATH = REPO_ROOT / "scripts" / "unused_intl_keys.json"
_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def dart_identifiers() -> set[str]:
    """Every identifier on the non-comment lines of tracked Dart code outside lib/l10n/."""
    grep = subprocess.run(
        ["git", "grep", "-h", "-v", "-E", r"^[[:space:]]*//", "--", "*.dart", ":!lib/l10n/"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return set(_IDENTIFIER.findall(grep.stdout))


def main() -> int:
    keys = translation_keys(TEMPLATE_ARB)
    if not keys:
        sys.exit(f"Error: no translation keys parsed from {TEMPLATE_ARB}; refusing to report none as unused.")

    referenced = dart_identifiers()
    unused = sorted(key for key in keys if key not in referenced)

    print(f"Checked {len(keys)} keys from {TEMPLATE_ARB.name}: {len(unused)} unused.")
    for key in unused:
        print(f"  - {key}")

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(
            {"unused_keys": unused, "count": len(unused), "source_file": str(TEMPLATE_ARB)},
            f,
            indent=2,
            ensure_ascii=False,
        )
        f.write("\n")
    print(f"\nWrote {OUTPUT_PATH.relative_to(REPO_ROOT)}. Review it before running remove_unused_intl_keys.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

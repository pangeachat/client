#!/usr/bin/env python3
"""
Remove the keys listed by find_unused_intl_keys.py from every .arb file.

Each key goes with its `@key` metadata entry. Every other line of each file is
left exactly as it was.

Usage:
    python3 scripts/remove_unused_intl_keys.py

Input:
    scripts/unused_intl_keys.json - written by find_unused_intl_keys.py
"""

import json
import sys

from arb_file import REPO_ROOT, remove_from_every_arb

INPUT_PATH = REPO_ROOT / "scripts" / "unused_intl_keys.json"


def main() -> int:
    if not INPUT_PATH.exists():
        print(f"Error: Could not find {INPUT_PATH}")
        print("Please run find_unused_intl_keys.py first to generate the list of unused keys.")
        return 1

    with open(INPUT_PATH, encoding="utf-8") as f:
        unused_keys = json.load(f)["unused_keys"]
    print(f"Removing {len(unused_keys)} unused keys.\n")

    total_removed = remove_from_every_arb(unused_keys)
    print(f"\nTotal keys/metadata entries removed: {total_removed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

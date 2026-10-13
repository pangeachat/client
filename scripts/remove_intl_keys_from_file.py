#!/usr/bin/env python3
"""
Script to remove all translation keys from one .arb file that exist in another .arb file.

This script:
1. Takes two .arb files as input:
   - A source file containing keys to remove
   - A target file to clean
2. Removes every entry of the target whose name the source also has, `@key`
   metadata included; the `@@` file entries (`@@locale`) are never removed
3. Leaves every other line of the target exactly as it was

Usage:
    python3 scripts/remove_intl_keys_from_file.py <source.arb> <target.arb>

Example:
    python3 scripts/remove_intl_keys_from_file.py app_en.arb app_es.arb
"""

import json
import sys

from arb_file import L10N_DIR, remove_entries


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python3 scripts/remove_intl_keys_from_file.py <source.arb> <target.arb>")
        return 1

    source_path = L10N_DIR / sys.argv[1]
    target_path = L10N_DIR / sys.argv[2]

    if not source_path.exists():
        print(f"Error: Source file not found: {source_path}")
        return 1

    if not target_path.exists():
        print(f"Error: Target file not found: {target_path}")
        return 1

    with open(source_path, encoding="utf-8") as f:
        names = {name for name in json.load(f) if not name.startswith("@@")}

    removed = remove_entries(target_path, names)

    if not removed:
        print("No matching keys found. Target file unchanged.")
        return 0

    print(f"Removed {len(removed)} entries from {target_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

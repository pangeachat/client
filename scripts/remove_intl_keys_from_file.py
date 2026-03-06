#!/usr/bin/env python3
"""
Script to remove all translation keys from one .arb file that exist in another .arb file.

This script:
1. Takes two .arb files as input:
   - A source file containing keys to remove
   - A target file to clean
2. Removes all matching keys from the target file
3. Removes corresponding metadata entries (keys starting with @)
4. Preserves key order and file structure

Usage:
    python3 scripts/remove_intl_keys_from_file.py <source.arb> <target.arb>

Example:
    python3 scripts/remove_intl_keys_from_file.py app_en.arb app_es.arb
"""

import json
import sys
from pathlib import Path
from collections import OrderedDict


def load_arb(path: Path) -> OrderedDict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def remove_keys(source_arb: OrderedDict, target_arb: OrderedDict) -> int:
    """
    Remove all keys from target_arb that exist in source_arb.

    Includes both normal keys and metadata keys.
    """
    keys_to_remove = set(source_arb.keys())
    removed = 0

    for key in list(target_arb.keys()):
        if key in keys_to_remove:
            del target_arb[key]
            removed += 1

    return removed


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python3 scripts/remove_intl_keys_from_file.py <source.arb> <target.arb>")
        return 1
    
    repo_path = Path(__file__).parent.parent.absolute()
    l10n_dir = repo_path / 'lib' / 'l10n'

    source_path = l10n_dir / sys.argv[1]
    target_path = l10n_dir / sys.argv[2]

    if not source_path.exists():
        print(f"Error: Source file not found: {source_path}")
        return 1

    if not target_path.exists():
        print(f"Error: Target file not found: {target_path}")
        return 1

    source_arb = load_arb(source_path)
    target_arb = load_arb(target_path)

    removed_count = remove_keys(source_arb, target_arb)

    if removed_count == 0:
        print("No matching keys found. Target file unchanged.")
        return 0

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(target_arb, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Removed {removed_count} entries from {target_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

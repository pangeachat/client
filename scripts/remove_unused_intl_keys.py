#!/usr/bin/env python3
"""
Script to remove unused translation keys from all .arb files.

This script:
1. Reads the unused keys from unused_intl_keys.json
2. Removes those keys and their metadata entries from all .arb files
3. Preserves the overall order and structure of the files

Usage:
    python3 scripts/remove_unused_intl_keys.py

Input:
    scripts/unused_intl_keys.json - JSON file containing the list of unused keys
    
Output:
    Updates all .arb files in lib/l10n/ by removing unused keys and their metadata
"""

import json
from pathlib import Path
from typing import List, Set
from collections import OrderedDict


def load_unused_keys(json_path: str) -> List[str]:
    """
    Load the list of unused keys from the JSON file.
    
    Args:
        json_path: Path to the unused_intl_keys.json file
    
    Returns:
        List of unused key names
    """
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return data['unused_keys']


def remove_keys_from_arb_file(arb_file_path: str, keys_to_remove: Set[str]) -> int:
    """
    Remove specified keys and their metadata from an .arb file.
    
    This function removes both the key-value pairs and their corresponding
    metadata entries (which are prefixed with @).
    
    Args:
        arb_file_path: Path to the .arb file
        keys_to_remove: Set of key names to remove
    
    Returns:
        Number of keys removed from this file
    """
    # Read the JSON file
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f, object_pairs_hook=OrderedDict)
    
    # Track what we remove
    removed_count = 0
    keys_to_delete = []
    
    # Identify all keys to remove (including metadata keys)
    for key in data.keys():
        # Check if this is a metadata key (starts with @)
        if key.startswith('@'):
            # Get the base key name
            base_key = key[1:]
            # Remove if the base key is in our removal list
            if base_key in keys_to_remove:
                keys_to_delete.append(key)
                removed_count += 1
        else:
            # Remove if the key itself is in our removal list
            if key in keys_to_remove:
                keys_to_delete.append(key)
                removed_count += 1
    
    # Remove the keys
    for key in keys_to_delete:
        del data[key]
    
    # Write back to file with proper formatting
    with open(arb_file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')  # Add trailing newline
    
    return removed_count


def main():
    """Main function to remove unused keys from all .arb files."""
    # Get repository root
    repo_path = Path(__file__).parent.parent.absolute()
    json_path = repo_path / 'scripts' / 'unused_intl_keys.json'
    l10n_dir = repo_path / 'lib' / 'l10n'
    
    if not json_path.exists():
        print(f"Error: Could not find {json_path}")
        print("Please run find_unused_intl_keys.py first to generate the list of unused keys.")
        return 1
    
    # Load unused keys
    print("Loading unused keys from JSON file...")
    unused_keys = load_unused_keys(str(json_path))
    keys_to_remove = set(unused_keys)
    print(f"Found {len(keys_to_remove)} unused keys to remove.\n")
    
    # Get all .arb files
    arb_files = sorted(l10n_dir.glob('*.arb'))
    print(f"Found {len(arb_files)} .arb files to process.\n")
    
    if not arb_files:
        print(f"Error: No .arb files found in {l10n_dir}")
        return 1
    
    # Process each .arb file
    total_removed = 0
    print("Processing .arb files...")
    print("=" * 80)
    
    for arb_file in arb_files:
        removed = remove_keys_from_arb_file(str(arb_file), keys_to_remove)
        total_removed += removed
        print(f"{arb_file.name}: Removed {removed} keys/metadata entries")
    
    print("=" * 80)
    print(f"\nTotal keys/metadata entries removed: {total_removed}")
    print(f"Processed {len(arb_files)} .arb files successfully.")
    
    return 0


if __name__ == '__main__':
    exit(main())

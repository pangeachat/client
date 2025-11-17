#!/usr/bin/env python3
"""
Script to remove a specific translation key from all .arb files.

This script:
1. Takes a key name as a command-line argument
2. Removes that key and its metadata entry from all .arb files
3. Preserves the overall order and structure of the files

Usage:
    python3 scripts/remove_intl_key.py <key_name>

Example:
    python3 scripts/remove_intl_key.py "obsoleteKey"

Input:
    key_name - The name of the key to remove (without the @ prefix for metadata)
    
Output:
    Updates all .arb files in lib/l10n/ by removing the specified key and its metadata
"""

import json
import sys
from pathlib import Path
from collections import OrderedDict


def remove_key_from_arb_file(arb_file_path: str, key_to_remove: str) -> int:
    """
    Remove a specific key and its metadata from an .arb file.
    
    This function removes both the key-value pair and its corresponding
    metadata entry (which is prefixed with @).
    
    Args:
        arb_file_path: Path to the .arb file
        key_to_remove: Name of the key to remove
    
    Returns:
        Number of entries removed from this file (0-2: key and/or metadata)
    """
    # Read the JSON file
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f, object_pairs_hook=OrderedDict)
    
    # Track what we remove
    removed_count = 0
    keys_to_delete = []
    
    # Check if the main key exists
    if key_to_remove in data:
        keys_to_delete.append(key_to_remove)
        removed_count += 1
    
    # Check if the metadata key exists
    metadata_key = f"@{key_to_remove}"
    if metadata_key in data:
        keys_to_delete.append(metadata_key)
        removed_count += 1
    
    # Remove the keys
    for key in keys_to_delete:
        del data[key]
    
    # Only write back if we actually removed something
    if removed_count > 0:
        with open(arb_file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')  # Add trailing newline
    
    return removed_count


def validate_key_name(key_name: str) -> str:
    """
    Validate and clean the key name.
    
    Args:
        key_name: The key name provided by the user
    
    Returns:
        Cleaned key name (without @ prefix if it was provided)
    
    Raises:
        ValueError: If the key name is invalid
    """
    if not key_name:
        raise ValueError("Key name cannot be empty")
    
    # Remove @ prefix if user accidentally included it
    if key_name.startswith('@'):
        key_name = key_name[1:]
    
    # Check if key name is still valid after cleaning
    if not key_name:
        raise ValueError("Key name cannot be just '@'")
    
    # Validate key name format (basic validation)
    if not key_name.replace('_', '').replace('-', '').isalnum():
        print(f"Warning: Key name '{key_name}' contains special characters. This might not match any existing keys.")
    
    return key_name


def main():
    """Main function to remove a specific key from all .arb files."""
    # Check command line arguments
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/remove_intl_key.py <key_name>")
        print("Example: python3 scripts/remove_intl_key.py \"obsoleteKey\"")
        return 1
    
    # Get and validate the key name
    try:
        key_to_remove = validate_key_name(sys.argv[1])
    except ValueError as e:
        print(f"Error: {e}")
        return 1
    
    # Get repository root
    repo_path = Path(__file__).parent.parent.absolute()
    l10n_dir = repo_path / 'lib' / 'l10n'
    
    if not l10n_dir.exists():
        print(f"Error: Could not find l10n directory at {l10n_dir}")
        return 1
    
    # Get all .arb files
    arb_files = sorted(l10n_dir.glob('*.arb'))
    print(f"Found {len(arb_files)} .arb files to process.")
    
    if not arb_files:
        print(f"Error: No .arb files found in {l10n_dir}")
        return 1
    
    # Ask for confirmation
    print(f"\nAbout to remove key '{key_to_remove}' and its metadata '@{key_to_remove}' from all .arb files.")
    confirm = input("Do you want to continue? (y/N): ").lower().strip()
    
    if confirm not in ['y', 'yes']:
        print("Operation cancelled.")
        return 0
    
    # Process each .arb file
    total_removed = 0
    files_modified = 0
    print("\nProcessing .arb files...")
    print("=" * 80)
    
    for arb_file in arb_files:
        removed = remove_key_from_arb_file(str(arb_file), key_to_remove)
        total_removed += removed
        if removed > 0:
            files_modified += 1
            entries = "entry" if removed == 1 else "entries"
            print(f"{arb_file.name}: Removed {removed} {entries}")
        else:
            print(f"{arb_file.name}: Key not found")
    
    print("=" * 80)
    print(f"\nSummary:")
    print(f"Total entries removed: {total_removed}")
    print(f"Files modified: {files_modified}")
    print(f"Files processed: {len(arb_files)}")
    
    if total_removed == 0:
        print(f"\nWarning: No occurrences of key '{key_to_remove}' were found in any .arb files.")
        print("Please check that the key name is correct and exists in the files.")
    else:
        print(f"\nSuccessfully removed key '{key_to_remove}' from all .arb files.")
    
    return 0


if __name__ == '__main__':
    exit(main())
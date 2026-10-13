#!/usr/bin/env python3
"""
Script to remove one or more translation keys from all .arb files.

This script:
1. Takes a key name as a command-line argument, or a file containing key names
2. Removes those keys and their metadata entries from all .arb files
3. Leaves every other line of each file exactly as it was

Usage:
    python3 scripts/remove_intl_key.py <key_name>
    python3 scripts/remove_intl_key.py --file <keys_file>

Examples:
    python3 scripts/remove_intl_key.py "obsoleteKey"
    python3 scripts/remove_intl_key.py --file keys_to_remove.txt

Input:
    key_name  - The name of the key to remove (without the @ prefix for metadata)
    keys_file - A plain-text file with one key name per line (blank lines and
                lines starting with # are ignored)

Output:
    Updates all .arb files in lib/l10n/ by removing the specified keys and their metadata
"""

import sys
from pathlib import Path

from arb_file import remove_from_every_arb


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


def load_keys_from_file(file_path: str) -> list[str]:
    """
    Load key names from a plain-text file (one key per line).

    Blank lines and lines starting with '#' are ignored.

    Args:
        file_path: Path to the keys file

    Returns:
        List of validated key names

    Raises:
        FileNotFoundError: If the file does not exist
        ValueError: If any key name is invalid
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Keys file not found: {file_path}")

    keys = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            keys.append(validate_key_name(line))

    return keys


def main():
    """Main function to remove one or more keys from all .arb files."""
    # Check command line arguments
    if len(sys.argv) == 3 and sys.argv[1] == '--file':
        try:
            keys_to_remove = load_keys_from_file(sys.argv[2])
        except (FileNotFoundError, ValueError) as e:
            print(f"Error: {e}")
            return 1
        if not keys_to_remove:
            print("Error: Keys file is empty or contains only comments.")
            return 1
    elif len(sys.argv) == 2 and sys.argv[1] != '--file':
        try:
            keys_to_remove = [validate_key_name(sys.argv[1])]
        except ValueError as e:
            print(f"Error: {e}")
            return 1
    else:
        print("Usage: python3 scripts/remove_intl_key.py <key_name>")
        print("       python3 scripts/remove_intl_key.py --file <keys_file>")
        print("Example: python3 scripts/remove_intl_key.py \"obsoleteKey\"")
        print("Example: python3 scripts/remove_intl_key.py --file keys_to_remove.txt")
        return 1

    # Ask for confirmation
    if len(keys_to_remove) == 1:
        print(f"\nAbout to remove key '{keys_to_remove[0]}' and its metadata '@{keys_to_remove[0]}' from all .arb files.")
    else:
        print(f"\nAbout to remove {len(keys_to_remove)} keys (and their metadata) from all .arb files:")
        for k in keys_to_remove:
            print(f"  - {k}")
    confirm = input("\nDo you want to continue? (y/N): ").lower().strip()

    if confirm not in ['y', 'yes']:
        print("Operation cancelled.")
        return 0

    print("\nProcessing .arb files...")
    print("=" * 80)
    total_removed = remove_from_every_arb(keys_to_remove)
    print("=" * 80)
    print(f"\nTotal entries removed: {total_removed}")

    if total_removed == 0:
        print(f"\nWarning: None of the specified keys were found in any .arb files.")
        print("Please check that the key names are correct and exist in the files.")
    else:
        print(f"\nSuccessfully removed {len(keys_to_remove)} key(s) from all .arb files.")

    return 0


if __name__ == '__main__':
    exit(main())
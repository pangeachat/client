#!/usr/bin/env python3
"""
Script to find unused translation keys in intl_en.arb after line 3243.

This script:
1. Reads intl_en.arb and extracts all translation keys after line 3243
2. Filters out metadata keys (those starting with @)
3. Searches the repository for references to each key
4. Returns a JSON file with unused keys

Usage:
    python3 scripts/find_unused_intl_keys.py

Output:
    scripts/unused_intl_keys.json - JSON file containing the list of unused keys
"""

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Set, List


def extract_keys_after_line(arb_file_path: str, start_line: int = 3243) -> List[str]:
    """
    Extract translation keys from .arb file after a specific line.
    
    ARB files are JSON files where keys starting with @ are metadata.
    We only want the actual translation keys (non-@ keys), not placeholder
    keys or other nested metadata fields.
    
    This function extracts only TOP-LEVEL keys that first appear after the
    specified line number. Keys that appear as placeholders are ignored.
    
    Args:
        arb_file_path: Path to the .arb file
        start_line: Line number to start extracting from (1-indexed)
    
    Returns:
        List of translation key names
    """
    # Load the entire JSON to get proper structure
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # Read file again to get line numbers for each key
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    keys = []
    
    # Extract only top-level keys (not nested keys inside metadata)
    for key in data.keys():
        # Skip metadata keys (those starting with @)
        if key.startswith('@'):
            continue
        
        # Find the FIRST occurrence of this key as a top-level definition
        # A top-level key appears at the start of a line (after whitespace)
        # with the pattern: "keyName": (not nested inside another object)
        for line_num, line in enumerate(lines, start=1):
            # Match key at the beginning of a line (indentation level 1)
            # This ensures we're matching top-level keys, not nested ones
            if re.match(r'^  "' + re.escape(key) + r'":\s*', line):
                # Only include keys that appear after the specified line
                if line_num > start_line:
                    keys.append(key)
                break
    
    return keys


def search_key_in_repository(key: str, repo_path: str, exclude_dirs: Set[str]) -> bool:
    """
    Search for a key in the repository using git grep for efficiency.
    
    Args:
        key: Translation key to search for
        repo_path: Path to the repository root
        exclude_dirs: Set of directory names to exclude from search
    
    Returns:
        True if the key is found, False otherwise
    """
    try:
        # Use git grep for fast searching, excluding the l10n directory
        # We search for the key name as it would appear in Dart code
        result = subprocess.run(
            ['git', 'grep', '-q', key],
            cwd=repo_path,
            capture_output=True,
            text=True
        )
        
        # git grep returns 0 if found, 1 if not found
        if result.returncode == 0:
            # Found the key, but we need to verify it's not just in the .arb files
            # Run again with output to check the files
            result_with_output = subprocess.run(
                ['git', 'grep', '-l', key],
                cwd=repo_path,
                capture_output=True,
                text=True
            )
            
            # Check if any non-.arb files contain the key
            files = result_with_output.stdout.strip().split('\n')
            for file in files:
                if not file.endswith('.arb'):
                    return True
            
            return False
        else:
            return False
            
    except subprocess.CalledProcessError:
        return False


def find_unused_keys(arb_file_path: str, repo_path: str, start_line: int = 3243) -> List[str]:
    """
    Find unused translation keys in the repository.
    
    Args:
        arb_file_path: Path to the .arb file
        repo_path: Path to the repository root
        start_line: Line number to start checking from
    
    Returns:
        List of unused keys
    """
    # Directories to exclude from search
    exclude_dirs = {'.git', 'build', 'node_modules', '.dart_tool', 'l10n'}
    
    print(f"Extracting keys from {arb_file_path} after line {start_line}...")
    keys = extract_keys_after_line(arb_file_path, start_line)
    print(f"Found {len(keys)} translation keys to check.\n")
    
    unused_keys = []
    used_count = 0
    
    print("Searching repository for key references...")
    for i, key in enumerate(keys, 1):
        # Print progress every 10 keys
        if i % 10 == 0:
            print(f"  Checked {i}/{len(keys)} keys...")
        
        if search_key_in_repository(key, repo_path, exclude_dirs):
            used_count += 1
        else:
            unused_keys.append(key)
    
    print(f"\nSearch complete!")
    print(f"Total keys checked: {len(keys)}")
    print(f"Used keys: {used_count}")
    print(f"Unused keys: {len(unused_keys)}")
    
    return unused_keys


def main():
    """Main function to run the unused key finder."""
    # Get repository root
    repo_path = Path(__file__).parent.parent.absolute()
    arb_file_path = repo_path / 'lib' / 'l10n' / 'intl_en.arb'
    
    if not arb_file_path.exists():
        print(f"Error: Could not find {arb_file_path}")
        return 1
    
    # Find unused keys starting from line 3243
    unused_keys = find_unused_keys(str(arb_file_path), str(repo_path), start_line=3243)
    
    # Print results
    print("\n" + "="*80)
    print("RESULTS")
    print("="*80)
    
    if unused_keys:
        print(f"\nFound {len(unused_keys)} unused keys (not referenced in any .dart files):")
        print("-" * 80)
        for key in sorted(unused_keys):
            print(f"  - {key}")
    else:
        print("\nNo unused keys found! All keys are referenced in the codebase.")
    
    # Save results to JSON file
    output_file = repo_path / 'scripts' / 'unused_intl_keys.json'
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump({
            'unused_keys': sorted(unused_keys),
            'count': len(unused_keys),
            'source_file': str(arb_file_path),
            'start_line': 3243
        }, f, indent=2, ensure_ascii=False)
    
    print(f"\nJSON output saved to: {output_file}")
    
    return 0


if __name__ == '__main__':
    exit(main())

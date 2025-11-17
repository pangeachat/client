#!/usr/bin/env python3
"""
Script to find unused translation keys in intl_en.arb after line 3243.

This script:
1. Reads intl_en.arb and extracts all translation keys after line 3243
2. Searches the repository for references to each key
3. Returns a list of keys that aren't referenced anywhere

Usage:
    python3 scripts/find_unused_intl_keys.py
"""

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Set, List, Dict


def extract_keys_after_line(arb_file_path: str, start_line: int = 3243) -> List[str]:
    """
    Extract translation keys from .arb file after a specific line.
    
    ARB files are JSON files where keys starting with @ are metadata.
    We only want the actual translation keys (non-@ keys).
    
    Args:
        arb_file_path: Path to the .arb file
        start_line: Line number to start extracting from (1-indexed)
    
    Returns:
        List of translation key names
    """
    keys = []
    
    with open(arb_file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Start from the specified line (convert to 0-indexed)
    for line_num, line in enumerate(lines[start_line - 1:], start=start_line):
        # Look for keys in JSON format: "keyName": "value"
        # Skip metadata keys (those starting with @)
        match = re.match(r'\s*"([^@][^"]+)":\s*["{]', line)
        if match:
            key = match.group(1)
            keys.append(key)
    
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


def find_unused_keys(arb_file_path: str, repo_path: str, start_line: int = 3243) -> Dict[str, List[str]]:
    """
    Find unused translation keys in the repository.
    
    Args:
        arb_file_path: Path to the .arb file
        repo_path: Path to the repository root
        start_line: Line number to start checking from
    
    Returns:
        Dictionary with 'unused' and 'used' lists of keys
    """
    # Directories to exclude from search
    exclude_dirs = {'.git', 'build', 'node_modules', '.dart_tool', 'l10n'}
    
    print(f"Extracting keys from {arb_file_path} after line {start_line}...")
    keys = extract_keys_after_line(arb_file_path, start_line)
    print(f"Found {len(keys)} translation keys to check.\n")
    
    unused_keys = []
    used_keys = []
    
    print("Searching repository for key references...")
    for i, key in enumerate(keys, 1):
        # Print progress every 10 keys
        if i % 10 == 0:
            print(f"  Checked {i}/{len(keys)} keys...")
        
        if search_key_in_repository(key, repo_path, exclude_dirs):
            used_keys.append(key)
        else:
            unused_keys.append(key)
    
    print(f"\nSearch complete!")
    
    return {
        'unused': unused_keys,
        'used': used_keys
    }


def main():
    """Main function to run the unused key finder."""
    # Get repository root
    repo_path = Path(__file__).parent.parent.absolute()
    arb_file_path = repo_path / 'lib' / 'l10n' / 'intl_en.arb'
    
    if not arb_file_path.exists():
        print(f"Error: Could not find {arb_file_path}")
        return 1
    
    # Find unused keys starting from line 3243
    results = find_unused_keys(str(arb_file_path), str(repo_path), start_line=3243)
    
    # Print results
    print("\n" + "="*80)
    print("RESULTS")
    print("="*80)
    
    print(f"\nTotal keys checked: {len(results['unused']) + len(results['used'])}")
    print(f"Used keys: {len(results['used'])}")
    print(f"Unused keys: {len(results['unused'])}\n")
    
    if results['unused']:
        print("UNUSED KEYS (not referenced in any .dart files):")
        print("-" * 80)
        for key in sorted(results['unused']):
            print(f"  - {key}")
    else:
        print("No unused keys found! All keys are referenced in the codebase.")
    
    # Save results to a file
    output_file = repo_path / 'scripts' / 'unused_intl_keys_report.txt'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("Unused Translation Keys Report\n")
        f.write("="*80 + "\n")
        f.write(f"Generated from: {arb_file_path}\n")
        f.write(f"Starting from line: 3243\n")
        f.write(f"Total keys checked: {len(results['unused']) + len(results['used'])}\n")
        f.write(f"Used keys: {len(results['used'])}\n")
        f.write(f"Unused keys: {len(results['unused'])}\n\n")
        
        if results['unused']:
            f.write("UNUSED KEYS:\n")
            f.write("-" * 80 + "\n")
            for key in sorted(results['unused']):
                f.write(f"{key}\n")
        
        if results['used']:
            f.write("\n\nUSED KEYS:\n")
            f.write("-" * 80 + "\n")
            for key in sorted(results['used']):
                f.write(f"{key}\n")
    
    print(f"\nDetailed report saved to: {output_file}")
    
    return 0


if __name__ == '__main__':
    exit(main())

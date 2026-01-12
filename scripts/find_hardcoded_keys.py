#!/usr/bin/env python3
"""
Script to find hardcoded json keys and replace with ModelKey equivalents

This script:
1. Reads model_keys.dart and extracts string values
2. Searches the repository for equivalent hardcoded strings
3. Replaces hardcoded strings with ModelKeys

Usage:
    python3 scripts/find_hardcoded_keys.py
"""

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Set, List

def extract_pairs(model_keys_path: str) -> List[(str, str)]:
    """
    Extract ModelKey names and string values from model_keys.dart file 

    ModelKey entries are of the form
        static const String name = 'value';
    or
        static const String name = "value";

    Args:
        model_keys_path: Path to model_keys.dart
    
    Returns:
        List of ModelKey names and string values, as tuples
    """
    pairs = []

    # Parse each entry for ModelKey name and value
    with open(model_keys_path, 'r') as f:
        file_content = f.read()

    reg_filter = re.compile("static[\n ]+const[\n ]+String[\n ]+[a-zA-Z0-9]+[\n ]+=[\n ]+[\"\'][a-zA-Z0-9_.]+[\"\'];")
    entries = reg_filter.findall(file_content)

    for entry in entries:
        parts = entry.strip().split()

        name = parts[3]
        value = parts[5]
        trimmed_value = value.strip(";\'\"")
        pairs.append((name, trimmed_value))

    return pairs

def search_and_replace(name: str, value: str, repo_path: str):
    """
    Search for a hardcoded ModelKey value in the repository,
    using git grep for efficiency.
    
    Replaces with ModelKey.name if found.
    
    Args:
        name: Name of ModelKey entry 
        value: ModelKey string value to search for and replace
        repo_path: Path to the repository root
    
    """
    search = "[\"\']" + value + "[\"\']"
    replace = "ModelKey." + name

    try:
        # Use git grep for fast searching
        # Find all files that contain the given hardcoded ModelKey value
        result = subprocess.run(
            ['git', 'grep', '-l', search],
            cwd=repo_path,
            capture_output=True,
            text=True
        )

        # Remove model_keys.dart and any non-dart files 
        files = result.stdout.strip().split('\n')
        for file in files:
            if ("model_keys.dart" not in file) & file.endswith('.dart'):
                with open(file, 'r+') as f:
                    file_content = f.read()

                    # Files without ModelKey import statements 
                    # may not need edits - leave to user discretion
                    import_str = "import 'package:fluffychat/pangea/common/constants/model_keys.dart';"
                    if import_str not in file_content:
                        print("The file " + file + " contains the text \"" + value + "\"")
                        # file_content = import_str + "\n" + file_content

                    else:
                        # Replace instances of hardcoded value in file
                        file_content = re.sub(search, replace, file_content)
                        f.seek(0)
                        f.write(file_content)
                        f.truncate()

    except subprocess.CalledProcessError:
        return False

def find_hardcoded_values(model_keys_path: str, repo_path: str):
    """
    Use helper functions to find hardcoded 
    ModelKey values and replace them.
    
    Args:
        model_keys_path: Path to model_keys.dart
        repo_path: Path to the repository root
    """
    # Find list of all ModelKeys to be searched for
    # as tuples of (name, value)
    pairs = extract_pairs(model_keys_path)
    
    print(f"Found {len(pairs)} ModelKeys to check.\n")
    
    print("Searching and replacing hardcoded ModelKey values...")
    for pair in pairs:
        search_and_replace(pair[0], pair[1], repo_path)
    print("Replacement complete")

def main():
    """Main function to run the hardcoded key replacement function."""
    # Get repository root
    repo_path = Path(__file__).parent.parent.absolute()
    model_keys_path = repo_path / 'lib' / 'pangea' / 'common' / 'constants' / 'model_keys.dart'

    if not model_keys_path.exists():
        print(f"Error: Could not find {model_keys_path}")
        return 1

    # Find list of all ModelKeys 
    # and replace any hardcoded values with ModelKey
    find_hardcoded_values(str(model_keys_path), str(repo_path))

    return 0

if __name__ == '__main__':
    exit(main())
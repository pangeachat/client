# Find Unused Translation Keys Script

This Python script helps identify unused translation keys in the `intl_en.arb` file that are not referenced anywhere in the codebase.

## Purpose

The script was created to clean up the internationalization (i18n) files by finding translation keys that are defined but never used. This helps maintain a cleaner codebase and reduces translation overhead.

## How It Works

1. **Extracts Keys**: Reads `lib/l10n/intl_en.arb` and extracts all translation keys after line 3243 (configurable)
2. **Filters Metadata**: Automatically excludes keys starting with `@` (metadata keys)
3. **Filters Placeholders**: Excludes nested placeholder keys inside metadata objects (e.g., `l1`, `l2`, `type`, `placeholders`)
4. **Searches Repository**: Uses `git grep` to efficiently search for each key in the repository
5. **Filters Results**: Excludes matches found only in `.arb` files (other language files)
6. **Reports Findings**: Generates a JSON file with the list of unused keys

## Usage

```bash
# Run from repository root
python3 scripts/find_unused_intl_keys.py
```

## Output

The script provides two types of output:

1. **Console Output**: Real-time progress and summary of findings
2. **JSON File**: List of unused keys saved to `scripts/unused_intl_keys.json`

### Sample Console Output

```
Extracting keys from /path/to/intl_en.arb after line 3243...
Found 1869 translation keys to check.

Searching repository for key references...
  Checked 10/1869 keys...
  ...
  
Search complete!
Total keys checked: 1869
Used keys: 1381
Unused keys: 488

================================================================================
RESULTS
================================================================================

Found 488 unused keys (not referenced in any .dart files):
--------------------------------------------------------------------------------
  - aaDisplayName
  - abDisplayName
  - acceptSelection
  ...
```

### Sample JSON Output

```json
{
  "unused_keys": [
    "aaDisplayName",
    "abDisplayName",
    "acceptSelection",
    ...
  ],
  "count": 488,
  "source_file": "/path/to/lib/l10n/intl_en.arb",
  "start_line": 3243
}
```

## Understanding the Results

- **Unused keys**: Translation keys that appear only in `.arb` files and nowhere else in the codebase
- **Metadata keys** (starting with `@`) are automatically excluded from the analysis
- **Placeholder keys** (nested inside metadata objects like `placeholders`) are automatically excluded

## Notes

- Keys starting with `@` are metadata and are automatically skipped
- Nested keys inside metadata objects (like `l1`, `l2` in placeholders) are automatically filtered out
- Only top-level translation keys are analyzed
- The script searches only for exact key matches in the repository
- False positives are possible if keys are constructed dynamically (e.g., using string interpolation)
- Always review the unused keys list before removing them from the translation files

## Customization

To check from a different line number, modify the `start_line` parameter in the `main()` function:

```python
unused_keys = find_unused_keys(str(arb_file_path), str(repo_path), start_line=3243)
```

## Requirements

- Python 3.x
- Git (for `git grep` command)
- Repository must be a git repository

## Next Steps

After identifying unused keys:

1. Review the unused keys list in `scripts/unused_intl_keys.json`
2. Determine which keys can be safely removed
3. Remove unused keys from `intl_en.arb`
4. Run the script again to verify
5. Consider removing the same keys from other language `.arb` files

## Related Files

- Source translation file: `lib/l10n/intl_en.arb`
- Other language files: `lib/l10n/intl_*.arb`
- Generated JSON output: `scripts/unused_intl_keys.json`

# Find Unused Translation Keys Script

This Python script helps identify unused translation keys in the `intl_en.arb` file that are not referenced anywhere in the codebase.

## Purpose

The script was created to clean up the internationalization (i18n) files by finding translation keys that are defined but never used. This helps maintain a cleaner codebase and reduces translation overhead.

## How It Works

1. **Extracts Keys**: Reads `lib/l10n/intl_en.arb` and extracts all translation keys after line 3243 (configurable)
2. **Searches Repository**: Uses `git grep` to efficiently search for each key in the repository
3. **Filters Results**: Excludes matches found only in `.arb` files (other language files)
4. **Reports Findings**: Generates a list of unused keys that can be safely removed

## Usage

```bash
# Run from repository root
python3 scripts/find_unused_intl_keys.py
```

## Output

The script provides two types of output:

1. **Console Output**: Real-time progress and summary of findings
2. **Report File**: Detailed report saved to `scripts/unused_intl_keys_report.txt`

### Sample Output

```
Extracting keys from /path/to/intl_en.arb after line 3243...
Found 1869 translation keys to check.

Searching repository for key references...
  Checked 10/1869 keys...
  ...
  
Search complete!

================================================================================
RESULTS
================================================================================

Total keys checked: 1869
Used keys: 1378
Unused keys: 491

UNUSED KEYS (not referenced in any .dart files):
--------------------------------------------------------------------------------
  - accountInformation
  - addGroupDescription
  - addNewFriend
  ...
```

## Understanding the Results

- **Used keys**: Translation keys that are referenced in `.dart` files
- **Unused keys**: Translation keys that appear only in `.arb` files and nowhere else in the codebase

## Notes

- Keys starting with `@` are metadata and are automatically skipped
- The script searches only for exact key matches in the repository
- False positives are possible if keys are constructed dynamically (e.g., using string interpolation)
- Always review the unused keys list before removing them from the translation files

## Customization

To check from a different line number, modify the `start_line` parameter in the `main()` function:

```python
results = find_unused_keys(str(arb_file_path), str(repo_path), start_line=3243)
```

## Requirements

- Python 3.x
- Git (for `git grep` command)
- Repository must be a git repository

## Next Steps

After identifying unused keys:

1. Review the unused keys list to ensure they can be safely removed
2. Remove unused keys from `intl_en.arb`
3. Run the script again to verify
4. Consider removing the same keys from other language `.arb` files

## Related Files

- Source translation file: `lib/l10n/intl_en.arb`
- Other language files: `lib/l10n/intl_*.arb`
- Generated report: `scripts/unused_intl_keys_report.txt`

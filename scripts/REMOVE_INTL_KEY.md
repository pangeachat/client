# Remove Translation Key Script

This script removes a specific translation key from all `.arb` files in the project.

## Usage

```bash
python3 scripts/remove_intl_key.py <key_name>
```

## Example

```bash
python3 scripts/remove_intl_key.py "obsoleteKey"
```

## What it does

1. **Takes a key name** as a command-line argument
2. **Validates the key name** and cleans it (removes @ prefix if accidentally provided)
3. **Searches all .arb files** in `lib/l10n/` directory
4. **Removes both the key and its metadata**:
   - The main key-value pair (e.g., `"myKey": "My Value"`)
   - The associated metadata entry (e.g., `"@myKey": {...}`)
5. **Preserves file structure** and formatting
6. **Provides detailed feedback** about what was removed

## Safety Features

- **Confirmation prompt** before making changes
- **Validates input** to prevent common mistakes
- **Detailed reporting** of what was removed from each file
- **Preserves JSON structure** and formatting
- **Only modifies files** that actually contain the key

## Output

The script provides:
- A list of processed files and what was removed from each
- Summary of total entries removed
- Warning if the key wasn't found in any files

## Related Scripts

- `find_unused_intl_keys.py` - Finds keys that are not used in the codebase
- `remove_unused_intl_keys.py` - Removes all unused keys at once
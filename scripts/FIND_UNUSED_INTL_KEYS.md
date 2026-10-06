# Find Unused Translation Keys Script

Lists the translation keys in `lib/l10n/intl_en.arb` that no Dart code references, so they can be removed before they are translated into every locale.

## Usage

```bash
# Run from repository root
python3 scripts/find_unused_intl_keys.py
```

It prints the unused keys and writes them to `scripts/unused_intl_keys.json` (gitignored), the input to `remove_unused_intl_keys.py`.

## How a key is judged

1. Every top-level key of `intl_en.arb` is checked, except `@key` metadata and `@@` file entries.
2. `git grep` collects every identifier on the tracked Dart lines outside `lib/l10n/` (where the generated `L10n` class lives), skipping lines that are `//` comments, so commented-out code does not keep a key alive.
3. A key whose name is not among those identifiers is unused.

The script exits with an error if it parses no keys at all, rather than reporting that nothing is unused.

## Limits

- The match errs towards "used". A dead key that shares its name with another identifier (`restricted`, which is also an enum value) or with a word in a trailing comment is not reported.
- e2e specs read keys out of `intl_en.arb` by name, but `e2e/check-locator-keys.js` already fails CI when a spec's key is not rendered by any Dart code.

## Next steps

1. Review `scripts/unused_intl_keys.json`.
2. Run `python3 scripts/remove_unused_intl_keys.py` to strip the keys from every locale.
3. Run `fvm flutter gen-l10n` and `fvm flutter analyze` to confirm nothing referenced a removed key.

"""Shared .arb reading and editing for the l10n key scripts.

Removal edits the file text instead of re-serializing the parsed JSON. The
locale arbs round-trip through json.dumps byte for byte, but intl_en.arb is
hand-edited and holds entries json.dumps would reflow, so a re-serialized
removal rewrites lines nobody asked to touch.
"""

import json
from collections.abc import Collection
from json.decoder import WHITESPACE, scanstring
from pathlib import Path
from typing import NamedTuple

REPO_ROOT = Path(__file__).resolve().parent.parent
L10N_DIR = REPO_ROOT / "lib" / "l10n"
TEMPLATE_ARB = L10N_DIR / "intl_en.arb"

_DECODER = json.JSONDecoder()


class _Entry(NamedTuple):
    name: str
    # Where the text joining this entry to the previous one begins: the end of
    # the previous entry's value, or this entry's own start for the first one.
    separator_start: int
    start: int
    end: int


def translation_keys(arb_path: Path) -> list[str]:
    """Names of the translations in `arb_path`, without `@` metadata or `@@` file entries."""
    with open(arb_path, encoding="utf-8") as f:
        return [name for name in json.load(f) if not name.startswith("@")]


def _skip_whitespace(text: str, pos: int) -> int:
    return WHITESPACE.match(text, pos).end()


def _top_level_entries(text: str) -> list[_Entry]:
    """Locate each member of the top-level object. `text` must already parse as JSON."""
    entries = []
    pos = _skip_whitespace(text, text.index("{") + 1)
    separator_start = pos
    while text[pos] != "}":
        if text[pos] == ",":
            pos = _skip_whitespace(text, pos + 1)
        name, after_name = scanstring(text, pos + 1)
        value_start = _skip_whitespace(text, text.index(":", after_name) + 1)
        _, end = _DECODER.raw_decode(text, value_start)
        entries.append(_Entry(name, separator_start, pos, end))
        separator_start = end
        pos = _skip_whitespace(text, end)
    return entries


def remove_entries(arb_path: Path, names: Collection[str]) -> list[str]:
    """Delete the named top-level entries from `arb_path`, leaving every other byte as it was.

    Returns the names removed. The file is left unwritten when none are present.
    """
    with open(arb_path, encoding="utf-8", newline="") as f:
        text = f.read()
    original = json.loads(text, object_pairs_hook=list)
    entries = _top_level_entries(text)
    removed = [entry.name for entry in entries if entry.name in names]
    if not removed:
        return []

    kept = [entry for entry in entries if entry.name not in names]
    pieces = [text[: entries[0].start]]
    for index, entry in enumerate(kept):
        pieces.append(text[(entry.separator_start if index else entry.start) : entry.end])
    pieces.append(text[entries[-1].end :])
    edited = "".join(pieces)

    expected = [pair for pair in original if pair[0] not in names]
    if json.loads(edited, object_pairs_hook=list) != expected:
        raise RuntimeError(f"{arb_path}: removing {removed} would change entries outside them")
    with open(arb_path, "w", encoding="utf-8", newline="") as f:
        f.write(edited)
    return removed


def remove_from_every_arb(keys: Collection[str]) -> int:
    """Remove each key and its `@key` metadata from every arb in lib/l10n/; returns the entries removed."""
    arb_paths = sorted(L10N_DIR.glob("*.arb"))
    if not arb_paths:
        raise FileNotFoundError(f"No .arb files in {L10N_DIR}")
    names = {name for key in keys for name in (key, f"@{key}")}
    total = 0
    for arb_path in arb_paths:
        removed = remove_entries(arb_path, names)
        print(f"{arb_path.name}: removed {len(removed)} entries")
        total += len(removed)
    return total

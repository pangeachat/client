#!/usr/bin/env python3
"""
Accessibility floor-check.

Fails when an interactive or image widget is missing the accessible affordance the
project's naming contracts require (see
.github/instructions/accessibility.instructions.md):

  - IconButton / FloatingActionButton must have `tooltip:` (their accessible name)
  - Image.network/asset/file/memory must have `semanticLabel:` (describe it) or
    `excludeFromSemantics: true` (decorative)

Modes:
  a11y_floor_check.py              scan the whole lib/ tree (the CI gate)
  a11y_floor_check.py --diff BASE  scan only lines added vs BASE (default origin/main)

Put `// a11y-ignore: <reason>` on the constructor line to suppress a genuine false
positive (for example an image wrapped by an ancestor ExcludeSemantics).
"""

import glob
import re
import subprocess
import sys

WINDOW = 25  # lines after the constructor to scan for the required argument

CHECKS = [
    (
        # Real button constructors only: IconButton(, .filled(, .outlined(,
        # FloatingActionButton(, .small(, .extended(, etc. NOT `.styleFrom(`
        # (a ButtonStyle builder, not a widget).
        re.compile(r"\b(IconButton|FloatingActionButton)(\.(?!styleFrom)\w+)?\("),
        ["tooltip:"],
        "IconButton/FloatingActionButton needs a `tooltip:` (its accessible name).",
    ),
    (
        re.compile(r"\bImage\.(network|asset|file|memory)\("),
        ["semanticLabel:", "excludeFromSemantics"],
        "Image needs a `semanticLabel:` (describe it) or `excludeFromSemantics: true` (decorative).",
    ),
]


def arg_block(src, line_idx, open_col):
    """The constructor's own parenthesized argument block (capped at WINDOW lines)."""
    depth, parts = 0, []
    for i in range(line_idx, min(line_idx + WINDOW, len(src))):
        seg = src[i][open_col:] if i == line_idx else src[i]
        parts.append(seg)
        for ch in seg:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return "\n".join(parts)
    return "\n".join(parts)


def diff_added(base):
    """Map of dart file path -> set of newly added line numbers, vs `base`."""
    diff = subprocess.run(
        ["git", "diff", "--unified=0", f"{base}...HEAD", "--", "lib"],
        capture_output=True, text=True,
    ).stdout
    if not diff.strip():
        diff = subprocess.run(
            ["git", "diff", "--unified=0", base, "--", "lib"],
            capture_output=True, text=True,
        ).stdout
    out, path, newline = {}, None, None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            newline = int(m.group(1)) if m else None
        elif line.startswith("+") and not line.startswith("+++"):
            if path and path.endswith(".dart") and newline is not None:
                out.setdefault(path, set()).add(newline)
                newline += 1
    return out


def sites(diff_base):
    """Yield (path, src_lines, line_index_0based) for the lines to check."""
    if diff_base is not None:
        for path, lines in diff_added(diff_base).items():
            try:
                src = open(path, encoding="utf-8", errors="ignore").read().splitlines()
            except OSError:
                continue
            for ln in sorted(lines):
                if ln - 1 < len(src):
                    yield path, src, ln - 1
    else:
        for path in glob.glob("lib/**/*.dart", recursive=True):
            src = open(path, encoding="utf-8", errors="ignore").read().splitlines()
            for i in range(len(src)):
                yield path, src, i


def main():
    diff_base = None
    if len(sys.argv) > 1 and sys.argv[1] == "--diff":
        diff_base = sys.argv[2] if len(sys.argv) > 2 else "origin/main"

    violations = []
    for path, src, i in sites(diff_base):
        text = src[i]
        if text.lstrip().startswith("//") or "a11y-ignore" in text:
            continue
        for pat, params, msg in CHECKS:
            m = pat.search(text)
            if m:
                block = arg_block(src, i, m.end() - 1)
                if not any(p in block for p in params):
                    violations.append((path, i + 1, msg, text.strip()[:80]))

    if not violations:
        print("a11y floor-check: no unlabeled controls. OK.")
        return 0

    print("a11y floor-check FAILED. Controls are missing an accessible name:\n")
    for path, ln, msg, snippet in violations:
        print(f"  {path}:{ln}")
        print(f"    {snippet}")
        print(f"    -> {msg}\n")
    print(
        "Add the affordance above, or (rarely, for a real false positive such as an "
        "image inside an ancestor ExcludeSemantics) put `// a11y-ignore: <reason>` on "
        "the constructor line.\n"
        f"Note: the argument scan stops after {WINDOW} lines, so an affordance further "
        "down a very long constructor can also need the ignore hatch.\n"
        "Contracts: .github/instructions/accessibility.instructions.md"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())

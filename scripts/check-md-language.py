#!/usr/bin/env python3
"""Report non-ASCII letters in every file tracked by git (see AGENTS.md, Rules 2 and 3).

Everything this repo ships — the .md files, and the templates a skill copies into a project —
is written in English, so a clean run prints nothing.

Matches Unicode *letters* only, so em dashes, arrows and box-drawing characters don't show up
as false positives. A plain `grep` character range over accented letters can't make that
distinction reliably: the shell's locale collation reorders the range, so it ends up swallowing
punctuation like the ellipsis and arrow characters too.

Usage: python3 scripts/check-md-language.py
Exits 1 if anything is found, so it can gate a commit.
"""

import subprocess
import sys
import unicodedata


def tracked_files():
    out = subprocess.run(
        ["git", "ls-files", "-z"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [p for p in out.split("\0") if p]


def main():
    hits = 0
    for path in tracked_files():
        try:
            with open(path, encoding="utf-8") as f:
                lines = list(enumerate(f, 1))
        except (UnicodeDecodeError, OSError):
            continue  # binary or unreadable — nothing to check
        for n, line in lines:
            found = {
                c for c in line
                if ord(c) > 127 and unicodedata.category(c).startswith("L")
            }
            if found:
                hits += 1
                print(f"{path}:{n}: {''.join(sorted(found))}  |  {line.strip()[:70]}")
    if hits:
        print(f"\n{hits} line(s) carry non-ASCII letters — translate them (AGENTS.md, Rules 2 and 3).")
        return 1
    print("Clean: no non-ASCII letters in any tracked file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

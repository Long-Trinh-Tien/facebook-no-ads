#!/usr/bin/env python3
"""
binary_diff.py - Compare 2 iOS binaries to find what changed.

Useful for tracking API changes between FB versions.
Run: dump_objc.py on both versions, then diff.

Usage:
    python3 binary_diff.py <old_dump.txt> <new_dump.txt>
"""
import sys
import re

def parse_dump(path):
    """Parse dump output from dump_objc.py (with filter)."""
    classes = {}
    current = None
    with open(path) as f:
        for line in f:
            line = line.rstrip()
            if line.startswith('@interface '):
                name = line[11:].strip().split()[0]
                current = name
                classes[name] = {'methods': [], 'ivars': []}
            elif line.startswith('    ') and current and not line.startswith('  '):
                # Method (indented 4 spaces)
                classes[current]['methods'].append(line.strip())
            elif line.startswith('  ivar: ') and current:
                classes[current]['ivars'].append(line[7:])
    return classes

def main():
    if len(sys.argv) < 3:
        print("Usage: binary_diff.py <old_dump.txt> <new_dump.txt>")
        sys.exit(1)

    old = parse_dump(sys.argv[1])
    new = parse_dump(sys.argv[2])

    removed_classes = set(old) - set(new)
    added_classes = set(new) - set(old)
    common = set(old) & set(new)

    print(f"=== Binary Diff ===")
    print(f"Old: {len(old)} classes")
    print(f"New: {len(new)} classes")
    print()

    if removed_classes:
        print(f"=== REMOVED CLASSES ({len(removed_classes)}) ===")
        for c in sorted(removed_classes):
            print(f"  - {c}")
        print()

    if added_classes:
        print(f"=== ADDED CLASSES ({len(added_classes)}) ===")
        for c in sorted(added_classes):
            print(f"  + {c}")
        print()

    # Check method/ivar changes in common classes
    method_changes = []
    ivar_changes = []
    for c in sorted(common):
        old_m = set(old[c]['methods'])
        new_m = set(new[c]['methods'])
        if old_m != new_m:
            added = new_m - old_m
            removed_m = old_m - new_m
            if added or removed_m:
                method_changes.append((c, added, removed_m))

        old_i = set(old[c]['ivars'])
        new_i = set(new[c]['ivars'])
        if old_i != new_i:
            added_i = new_i - old_i
            removed_i = old_i - new_i
            if added_i or removed_i:
                ivar_changes.append((c, added_i, removed_i))

    if method_changes:
        print(f"=== METHOD CHANGES ({len(method_changes)} classes) ===")
        for c, added, removed in method_changes:
            if added or removed:
                print(f"\n  {c}:")
                for m in sorted(added):
                    print(f"    + {m}")
                for m in sorted(removed):
                    print(f"    - {m}")
        print()

    if ivar_changes:
        print(f"=== IVAR CHANGES ({len(ivar_changes)} classes) ===")
        for c, added, removed in ivar_changes:
            if added or removed:
                print(f"\n  {c}:")
                for iv in sorted(added):
                    print(f"    + {iv}")
                for iv in sorted(removed):
                    print(f"    - {iv}")
        print()

    # Summary
    print("=== SUMMARY ===")
    print(f"Removed: {len(removed_classes)} classes")
    print(f"Added: {len(added_classes)} classes")
    print(f"Modified: {len(method_changes) + len(ivar_changes)} classes (method/ivar)")

if __name__ == '__main__':
    main()

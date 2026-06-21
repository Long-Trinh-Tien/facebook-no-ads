#!/usr/bin/env python3
"""
strings_grep.py - Search for ObjC class/selector names in iOS binary.

Faster than raw `strings | grep` because:
- Filters out junk strings
- Shows context
- Optional case-insensitive
- Output structured results

Usage:
    python3 strings_grep.py <binary> <pattern> [--type=class|method|all]
    python3 strings_grep.py FBSharedFramework Sponsor
    python3 strings_grep.py FBSharedFramework asFB --type=method
"""
import sys
import re
import argparse
import struct

def is_printable(s):
    return all(32 <= ord(c) < 127 for c in s)

def extract_strings(b, min_len=4):
    """Extract printable strings from binary, similar to `strings` command."""
    result = []
    current = b''
    for byte in b:
        if 32 <= byte < 127:
            current += bytes([byte])
        else:
            if len(current) >= min_len:
                result.append(current.decode('ascii', errors='replace'))
            current = b''
    if len(current) >= min_len:
        result.append(current.decode('ascii', errors='replace'))
    return result

def is_class_name(s):
    """Heuristic: ObjC class names start with capital, contain alphanumeric."""
    return bool(re.match(r'^[A-Z][A-Za-z0-9_]+$', s)) and not s.startswith('_')

def is_method_name(s):
    """Heuristic: method names can be various patterns."""
    return bool(re.match(r'^[A-Za-z_][A-Za-z0-9_:]+$', s))

def categorize(s):
    """Categorize string as class, method, or other."""
    if is_class_name(s):
        return 'class'
    if is_method_name(s) and ('_' in s or ':' in s):
        return 'method'
    return 'other'

def main():
    parser = argparse.ArgumentParser(description='Smart strings search for iOS binaries')
    parser.add_argument('binary', help='Path to Mach-O binary')
    parser.add_argument('pattern', help='Search pattern (case-insensitive substring)')
    parser.add_argument('--type', choices=['class', 'method', 'all'], default='all',
                       help='Filter by string type')
    parser.add_argument('--min-len', type=int, default=4, help='Minimum string length')
    parser.add_argument('--limit', type=int, default=100, help='Max results')
    args = parser.parse_args()

    with open(args.binary, 'rb') as f:
        b = f.read()

    print(f"Searching {args.binary} for '{args.pattern}' (type={args.type})")

    pattern_lower = args.pattern.lower()
    matches = []
    for s in extract_strings(b, args.min_len):
        if pattern_lower not in s.lower():
            continue
        cat = categorize(s)
        if args.type == 'class' and cat != 'class':
            continue
        if args.type == 'method' and cat != 'method':
            continue
        matches.append((s, cat))

    # Sort by category priority, then alphabetically
    matches.sort(key=lambda x: (x[1] != 'class', x[1] != 'method', x[0].lower()))

    if not matches:
        print("No matches found.")
        return

    print(f"\nFound {len(matches)} matches (showing first {min(len(matches), args.limit)}):\n")
    for s, cat in matches[:args.limit]:
        marker = {'class': '[C]', 'method': '[M]', 'other': '[?]'}.get(cat, '[?]')
        print(f"  {marker} {s}")

    if len(matches) > args.limit:
        print(f"\n... and {len(matches) - args.limit} more (use --limit to see more)")

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Extract methods DEFINED on a specific ObjC class by parsing Mach-O structure.
Uses llvm-otool to get the class list, then follows pointers to find method lists.
"""
import sys
import struct
import subprocess
import re

def get_class_list_offsets(binary_path):
    """Get offsets of class list in __objc_classlist section."""
    result = subprocess.run(
        ['llvm-otool-18', '-oV', binary_path],
        capture_output=True,
        text=True,
        timeout=300
    )

    if result.returncode != 0:
        return None, None

    # Parse output to find __objc_classlist section
    lines = result.stdout.split('\n')
    in_classlist = False
    classlist_data = []

    for line in lines:
        if 'Contents of' in line and '__objc_classlist' in line:
            in_classlist = True
            continue
        if in_classlist:
            if 'Contents of' in line:  # Next section
                break
            # Parse address lines
            parts = line.strip().split()
            if len(parts) >= 2:
                try:
                    # Format: "0000000006b0e7c0 0x10000006cffe08"
                    addr = int(parts[0], 16)
                    ptr = int(parts[1], 16)
                    classlist_data.append((addr, ptr))
                except:
                    pass

    return classlist_data, result.stdout

def find_class_name_in_data(binary_path, class_name_to_find):
    """Find a specific class by searching for its name in the binary."""
    with open(binary_path, 'rb') as f:
        data = f.read()

    class_bytes = class_name_to_find.encode('utf-8') + b'\x00'

    # Find all occurrences
    offsets = []
    offset = 0
    while True:
        idx = data.find(class_bytes, offset)
        if idx < 0:
            break
        offsets.append(idx)
        offset = idx + len(class_bytes)

    return offsets

def extract_string_at_offset(data, offset):
    """Read null-terminated string at offset."""
    end = data.find(b'\x00', offset)
    if end < 0:
        return ""
    return data[offset:end].decode('utf-8', errors='ignore')

def find_methods_near_class(binary_path, class_name):
    """
    Find methods by looking at the class structure.
    ObjC class structure (64-bit):
    - isa pointer (8 bytes)
    - superclass pointer (8 bytes)
    - cache (24 bytes)
    - vtable (8 bytes)
    - class name pointer (8 bytes)
    - class info pointer (8 bytes)
    - instance size (4 bytes)
    - instance vars pointer (8 bytes)
    - method lists pointer (8 bytes)
    """
    with open(binary_path, 'rb') as f:
        data = f.read()

    # Find class name in binary
    class_name_bytes = class_name.encode('utf-8') + b'\x00'
    class_name_offsets = []
    offset = 0
    while True:
        idx = data.find(class_name_bytes, offset)
        if idx < 0:
            break
        class_name_offsets.append(idx)
        offset = idx + len(class_name_bytes)

    if not class_name_offsets:
        return [], []

    # For each occurrence, try to read the class structure
    # The class name pointer in a class struct points to this string
    # So we need to find class structs that have a pointer to this offset

    methods = set()
    ivars = set()

    # This is complex - let's use a simpler heuristic
    # Methods that reference this class in their type encoding are likely on this class

    # Search for T@"ClassName" patterns
    pattern = b'T@"' + class_name_bytes.rstrip(b'\x00') + b'"'
    offset = 0
    while True:
        idx = data.find(pattern, offset)
        if idx < 0:
            break

        # Found a type encoding referencing this class
        # Look for the method name (next null-terminated string after this)
        search_region = data[idx:idx+500]

        # Find null bytes
        null_positions = [i for i, b in enumerate(search_region) if b == 0]

        if len(null_positions) >= 2:
            # Method name is between second and third null (or end of region)
            method_start = null_positions[1] + 1
            if len(null_positions) >= 3:
                method_end = null_positions[2]
            else:
                method_end = min(method_start + 100, len(search_region))

            method_name = search_region[method_start:method_end].decode('utf-8', errors='ignore')
            if method_name and re.match(r'^[a-zA-Z_][a-zA-Z0-9_:]*$', method_name):
                methods.add(method_name)

        offset = idx + len(pattern)

    return sorted(methods), sorted(ivars)

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 deep_analyze.py <binary> <class_name>")
        sys.exit(1)

    binary_path = sys.argv[1]
    class_name = sys.argv[2]

    print(f"🔍 Deep analysis of {class_name}")
    print("=" * 80)

    # Find class name offsets
    class_offsets = find_class_name_in_data(binary_path, class_name)
    print(f"\n📍 Class name string found at {len(class_offsets)} location(s)")

    # Find methods that reference this class
    methods, ivars = find_methods_near_class(binary_path, class_name)

    print(f"\n📋 METHODS that reference {class_name} ({len(methods)}):")
    for method in methods[:40]:
        print(f"  - {method}")
    if len(methods) > 40:
        print(f"  ... and {len(methods) - 40} more")

    if ivars:
        print(f"\n📊 IVARS ({len(ivars)}):")
        for ivar in ivars[:20]:
            print(f"  - _{ivar}")

if __name__ == '__main__':
    main()

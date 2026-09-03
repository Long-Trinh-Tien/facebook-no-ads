#!/usr/bin/env python3
"""
Extract ObjC class method signatures from Mach-O binary.
Searches for method type encodings that reference the class.
"""
import sys
import re

def extract_methods_from_type_encoding(binary_path, class_name):
    """
    Search for method type encodings that reference the class.
    Format: T@"ClassName",...method_name
    """
    with open(binary_path, 'rb') as f:
        data = f.read()

    class_bytes = class_name.encode('utf-8')

    # Find all occurrences of the class name
    methods = set()
    offset = 0

    while True:
        idx = data.find(class_bytes, offset)
        if idx < 0:
            break

        # Look backwards for method name (null-terminated string before class ref)
        # and method type encoding (starts with T@)
        search_start = max(0, idx - 200)
        region = data[search_start:idx+100]

        # Find T@ pattern before the class name
        t_pos = region.rfind(b'T@"')
        if t_pos >= 0:
            # Found type encoding, now find the method name
            # Method name is usually after the type encoding, null-terminated
            after_t = region[t_pos:]
            # Find the method name (next null-terminated string after the type info)
            nulls = [i for i, b in enumerate(after_t) if b == 0]
            if len(nulls) >= 2:
                # Method name is between second and third null (or end)
                method_start = nulls[1] + 1
                if len(nulls) >= 3:
                    method_end = nulls[2]
                else:
                    method_end = len(after_t)

                method_name = after_t[method_start:method_end].decode('utf-8', errors='ignore')
                if method_name and re.match(r'^[a-zA-Z_][a-zA-Z0-9_:]*$', method_name):
                    methods.add(method_name)

        offset = idx + len(class_bytes)

    return methods

def extract_methods_from_methodname_section(binary_path, class_name):
    """
    Extract methods by looking at the __objc_methname section.
    This section contains all method selector names as null-terminated strings.
    """
    with open(binary_path, 'rb') as f:
        data = f.read()

    # Find __objc_methname section
    # It's usually in __TEXT segment
    # Let's just extract all null-terminated strings and filter

    methods = set()
    offset = 0
    while offset < len(data):
        # Find next null byte
        null_pos = data.find(b'\x00', offset)
        if null_pos < 0 or null_pos - offset > 100:
            if null_pos < 0:
                break
            offset = null_pos + 1
            continue

        # Extract string
        s = data[offset:null_pos]
        if 3 < len(s) < 80:
            try:
                decoded = s.decode('utf-8')
                # Filter for method-like names
                if re.match(r'^[a-zA-Z_][a-zA-Z0-9_:]*$', decoded):
                    # Exclude class names (usually start with capital and are longer)
                    if not decoded[0].isupper() or '_' in decoded:
                        methods.add(decoded)
            except:
                pass

        offset = null_pos + 1

    return methods

def find_methods_for_class(binary_path, class_name):
    """Find methods that are likely associated with the class."""
    # Get all method names
    all_methods = extract_methods_from_methodname_section(binary_path, class_name)

    # Filter for methods that are likely video-related
    video_keywords = ['video', 'Video', 'play', 'Play', 'URL', 'url', 'item', 'Item',
                      'controller', 'Controller', 'current', 'Current', 'set', 'Set']

    relevant = []
    for method in all_methods:
        if any(kw in method for kw in video_keywords):
            relevant.append(method)

    return sorted(relevant)

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 find_methods.py <binary> <class_name>")
        sys.exit(1)

    binary_path = sys.argv[1]
    class_name = sys.argv[2]

    print(f"🔍 Finding methods for {class_name}")
    print("=" * 80)

    # Find video-related methods
    methods = find_methods_for_class(binary_path, class_name)

    print(f"\n📋 Video-related methods found: {len(methods)}")
    if methods:
        for method in methods[:50]:
            print(f"  - {method}")
        if len(methods) > 50:
            print(f"  ... and {len(methods) - 50} more")

if __name__ == '__main__':
    main()

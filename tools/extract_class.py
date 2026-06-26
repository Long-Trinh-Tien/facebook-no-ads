#!/usr/bin/env python3
"""
Extract detailed information about ObjC classes from llvm-otool output.
"""
import sys
import re
import subprocess

def get_objc_metadata(binary_path):
    """Run llvm-otool-18 and get ObjC metadata."""
    result = subprocess.run(
        ['llvm-otool-18', '-oV', binary_path],
        capture_output=True,
        text=True,
        timeout=300
    )
    return result.stdout

def extract_class_details(output, class_name):
    """Extract all references to a class - methods, ivars, properties."""
    lines = output.split('\n')

    methods = []
    ivars = []
    properties = []
    protocols = []

    # Method patterns: -[ClassName method] or +[ClassName method]
    method_pattern = re.compile(r'[-+]\[' + re.escape(class_name) + r'\s+([^\]]+)\]')

    # Ivar pattern: V_ivarName (with class reference nearby)
    ivar_pattern = re.compile(r'T@"[^"]+",[RCWN],?[RCWN]?,V_(\w+)')

    # Property pattern (look for V_propertyName)
    prop_pattern = re.compile(r',V(\w+)\s')

    for line in lines:
        # Extract methods
        match = method_pattern.search(line)
        if match:
            method_name = match.group(1).strip()
            # Filter out encoding patterns
            if not any(c in method_name for c in ['@', '#', ':', 'i', 'c', 's', 'l', 'q', 'f', 'd', 'B', 'v', '*']):
                methods.append(method_name)

        # Extract ivars (look for V_ pattern)
        for ivar_match in re.finditer(r'V_(\w+)', line):
            ivar_name = ivar_match.group(1)
            if ivar_name not in ivars and not ivar_name.startswith('_'):
                ivars.append(ivar_name)

    return {
        'methods': sorted(set(methods)),
        'ivars': sorted(set(ivars))
    }

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 extract_class.py <binary> <class_name>")
        sys.exit(1)

    binary_path = sys.argv[1]
    class_name = sys.argv[2]

    print(f"🔍 Analyzing {class_name} in {binary_path}")
    print("=" * 80)

    output = get_objc_metadata(binary_path)

    details = extract_class_details(output, class_name)

    print(f"\n📋 METHODS ({len(details['methods'])}):")
    for method in details['methods']:
        print(f"  - {method}")

    print(f"\n📊 IVARS ({len(details['ivars'])}):")
    for ivar in details['ivars']:
        print(f"  - _{ivar}")

if __name__ == '__main__':
    main()

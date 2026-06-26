#!/usr/bin/env python3
"""
Parse llvm-otool-18 ObjC metadata output to extract class details.
Usage: python3 parse_objc.py <binary> <class_name>
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
        timeout=180
    )
    return result.stdout

def find_class_section(output, class_name):
    """Find the section in otool output that describes a specific class."""
    lines = output.split('\n')
    in_target_class = False
    class_start = -1
    class_end = -1

    for i, line in enumerate(lines):
        # Look for class name pattern
        # Usually: name 0x... <class_name>
        if f'name 0x' in line and class_name in line:
            # Check if this is the start of a class definition
            # Look backwards for "Contents of" or class list
            for j in range(max(0, i-5), i):
                if 'Contents of' in lines[j] or 'classrefs' in lines[j].lower():
                    class_start = j
                    break
            in_target_class = True
            continue

        if in_target_class:
            # End of class section - look for next "name 0x" or section end
            if 'name 0x' in line and class_name not in line:
                class_end = i
                break
            if 'Contents of' in line and i > class_start + 10:
                class_end = i
                break

    if class_start >= 0:
        if class_end < 0:
            class_end = len(lines)
        return '\n'.join(lines[class_start:class_end])
    return None

def extract_methods_from_classref(output, class_name):
    """Extract methods that reference the given class."""
    methods = []
    lines = output.split('\n')

    # Pattern: -[ClassName methodName] or +[ClassName methodName]
    pattern = re.compile(r'[-+]\[' + re.escape(class_name) + r'\s+([^\]]+)\]')

    for line in lines:
        match = pattern.search(line)
        if match:
            method_name = match.group(1).strip()
            methods.append(method_name)

    return methods

def extract_ivars(output, class_name):
    """Extract ivar references for a class."""
    ivars = []
    lines = output.split('\n')

    # Pattern: T@"ClassName",...,V_ivarName
    pattern = re.compile(r'V_(\w+).*?' + re.escape(class_name))

    for line in lines:
        match = pattern.search(line)
        if match:
            ivar_name = match.group(1)
            ivars.append(ivar_name)

    return ivars

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 parse_objc.py <binary> <class_name>")
        sys.exit(1)

    binary_path = sys.argv[1]
    class_name = sys.argv[2]

    print(f"Analyzing {class_name} in {binary_path}...")
    print("=" * 80)

    output = get_objc_metadata(binary_path)

    # Find class section
    class_section = find_class_section(output, class_name)
    if class_section:
        print(f"\n📦 CLASS SECTION FOR {class_name}:")
        print(class_section[:2000])  # First 2000 chars
        print("...")
    else:
        print(f"❌ Class {class_name} not found in class definitions")

    # Extract methods
    methods = extract_methods_from_classref(output, class_name)
    if methods:
        print(f"\n🔧 METHODS ({len(methods)}):")
        for method in sorted(set(methods)):
            print(f"  - {method}")

    # Extract ivars
    ivars = extract_ivars(output, class_name)
    if ivars:
        print(f"\n📊 IVARS ({len(ivars)}):")
        for ivar in sorted(set(ivars)):
            print(f"  - _{ivar}")

if __name__ == '__main__':
    main()

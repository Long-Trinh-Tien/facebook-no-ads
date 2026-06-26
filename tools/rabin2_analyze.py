#!/usr/bin/env python3
"""
Extract ObjC class details using rabin2 and radare2.
Parses property/ivar definitions from __TEXT.__objc_methname section.
"""
import subprocess
import re
import sys

def extract_with_r2(binary_path, class_name):
    """Use radare2 to extract property/ivar definitions for a class."""
    # Get all strings that reference this class
    result = subprocess.run(
        ['r2', '-q', '-c', f'iz~{class_name}', binary_path],
        capture_output=True,
        text=True,
        timeout=300
    )

    lines = result.stdout.split('\n')

    properties = set()
    ivars = set()
    methods = set()

    for line in lines:
        # Look for type encoding patterns: T@"ClassName",...V_ivarName
        if 'T@"' + class_name + '"' in line:
            # Extract the full content
            match = re.search(r'ascii\s+(.+)', line)
            if match:
                content = match.group(1).strip()

                # Parse property/ivar definition
                # Format: T@"ClassName",[flags],V_ivarName
                parts = content.split(',')
                if len(parts) >= 3:
                    # Last part is usually the ivar name
                    ivar_name = parts[-1].strip()
                    if ivar_name.startswith('V_'):
                        ivars.add(ivar_name[2:])  # Remove V_ prefix
                    elif ivar_name.startswith('V'):
                        ivars.add(ivar_name[1:])

                # Check for property attributes
                if 'R' in content or 'W' in content or 'C' in content:
                    # This is a property declaration
                    if 'V_' in content:
                        prop_name = content.split('V_')[-1].strip()
                        if prop_name and len(prop_name) < 50:
                            properties.add(prop_name)

    return properties, ivars, methods

def extract_methods_with_rabin2(binary_path, class_name):
    """Use rabin2 to find method implementations."""
    result = subprocess.run(
        ['rabin2', '-s', binary_path],
        capture_output=True,
        text=True,
        timeout=300
    )

    lines = result.stdout.split('\n')

    # Look for ObjC method symbols: -[ClassName method] or +[ClassName method]
    pattern = re.compile(r'[-+]\[' + re.escape(class_name) + r'\s+([^\]]+)\]')

    methods = set()
    for line in lines:
        match = pattern.search(line)
        if match:
            method_name = match.group(1).strip()
            if method_name and len(method_name) < 100:
                methods.add(method_name)

    return methods

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 rabin2_analyze.py <binary>")
        print("Or: python3 rabin2_analyze.py <binary> <class_name>")
        sys.exit(1)

    binary_path = sys.argv[1]

    if len(sys.argv) >= 3:
        # Analyze specific class
        class_name = sys.argv[2]
        print(f"🔍 Analyzing {class_name}")
        print("=" * 80)

        # Get properties and ivars
        properties, ivars, _ = extract_with_r2(binary_path, class_name)

        # Get methods
        methods = extract_methods_with_rabin2(binary_path, class_name)

        print(f"\n📦 PROPERTIES ({len(properties)}):")
        for prop in sorted(properties):
            print(f"  - {prop}")

        print(f"\n📊 IVARS ({len(ivars)}):")
        for ivar in sorted(ivars):
            print(f"  - _{ivar}")

        print(f"\n🔧 METHODS ({len(methods)}):")
        for method in sorted(methods):
            print(f"  - {method}")
    else:
        # Analyze multiple key classes
        classes = [
            'FBVideoPlaybackContainerView',
            'FBVideoPlaybackController',
            'FBVideoPlaybackItem',
            'FBSnacksMediaContainerView',
            'FBSnacksNewVideoView',
            'FBShortsSideBarView',
            'FBShortsPlaybackController',
            'FBSnacksMediaPlayerManager'
        ]

        for class_name in classes:
            print(f"\n{'=' * 80}")
            print(f"📦 {class_name}")
            print('=' * 80)

            properties, ivars, _ = extract_with_r2(binary_path, class_name)
            methods = extract_methods_with_rabin2(binary_path, class_name)

            if properties:
                print(f"Properties: {', '.join(sorted(properties)[:10])}")
            if ivars:
                print(f"Ivars: {', '.join(sorted(ivars)[:10])}")
            if methods:
                print(f"Methods: {', '.join(sorted(methods)[:10])}")

if __name__ == '__main__':
    main()

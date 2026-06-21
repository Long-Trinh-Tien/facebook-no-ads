#!/usr/bin/env python3
"""
extract_ipa.py - Extract and prepare iOS IPA for analysis.

Unpacks IPA, finds main binary and frameworks, prepares for RE.

Usage:
    python3 extract_ipa.py <path_to.ipa> [output_dir]
"""
import sys
import os
import zipfile
import plistlib
import subprocess

def main():
    if len(sys.argv) < 2:
        print("Usage: extract_ipa.py <path_to.ipa> [output_dir]")
        sys.exit(1)

    ipa_path = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "extracted"

    if not os.path.exists(ipa_path):
        print(f"File not found: {ipa_path}")
        sys.exit(1)

    # Create output dir
    os.makedirs(out_dir, exist_ok=True)

    # Unzip IPA
    print(f"Extracting {ipa_path} → {out_dir}/...")
    with zipfile.ZipFile(ipa_path) as z:
        z.extractall(out_dir)

    # Find main app dir
    app_dirs = []
    for root, dirs, files in os.walk(out_dir):
        for d in dirs:
            if d.endswith('.app'):
                app_dirs.append(os.path.join(root, d))

    if not app_dirs:
        print("No .app directory found!")
        sys.exit(1)

    main_app = app_dirs[0]
    print(f"App: {main_app}")

    # Read Info.plist
    info_plist_path = os.path.join(main_app, 'Info.plist')
    if os.path.exists(info_plist_path):
        with open(info_plist_path, 'rb') as f:
            info = plistlib.load(f)
        print(f"\n=== App Info ===")
        print(f"  Bundle ID: {info.get('CFBundleIdentifier', 'N/A')}")
        print(f"  Name: {info.get('CFBundleName', 'N/A')}")
        print(f"  Display Name: {info.get('CFBundleDisplayName', 'N/A')}")
        print(f"  Version: {info.get('CFBundleShortVersionString', 'N/A')}")
        print(f"  Build: {info.get('CFBundleVersion', 'N/A')}")
        print(f"  Min iOS: {info.get('MinimumOSVersion', 'N/A')}")
        print(f"  Executable: {info.get('CFBundleExecutable', 'N/A')}")

    # Find main binary
    exe_name = info.get('CFBundleExecutable', 'Facebook') if os.path.exists(info_plist_path) else 'Facebook'
    exe_path = os.path.join(main_app, exe_name)
    if not os.path.exists(exe_path):
        # Try common names
        for name in os.listdir(main_app):
            if not name.startswith('.') and os.path.isfile(os.path.join(main_app, name)):
                exe_path = os.path.join(main_app, name)
                break

    if os.path.exists(exe_path):
        print(f"\n=== Main Binary ===")
        print(f"  Path: {exe_path}")
        size_mb = os.path.getsize(exe_path) / 1024 / 1024
        print(f"  Size: {size_mb:.1f} MB")

        # Check magic / arch
        with open(exe_path, 'rb') as f:
            magic = f.read(4)
        if magic == b'\xcf\xfa\xed\xfe':
            print(f"  Arch: arm64 (Mach-O 64-bit)")
        elif magic == b'\xce\xfa\xed\xfe':
            print(f"  Arch: arm32")

    # Find frameworks
    fw_dir = os.path.join(main_app, 'Frameworks')
    if os.path.exists(fw_dir):
        frameworks = [d for d in os.listdir(fw_dir) if d.endswith('.framework')]
        print(f"\n=== Frameworks ({len(frameworks)}) ===")
        for fw in sorted(frameworks):
            fw_path = os.path.join(fw_dir, fw)
            binary = fw.replace('.framework', '')
            binary_path = os.path.join(fw_path, binary)
            if os.path.exists(binary_path):
                size_mb = os.path.getsize(binary_path) / 1024 / 1024
                print(f"  {fw} ({size_mb:.1f} MB)")

    # Quick analysis suggestions
    print(f"\n=== Next steps ===")
    if os.path.exists(exe_path):
        print(f"  1. Class dump main binary:")
        print(f"     python3 tools/dump_objc.py {exe_path}")
    if os.path.exists(fw_dir):
        print(f"  2. Or dump specific framework:")
        print(f"     python3 tools/dump_objc.py {fw_dir}/FBSharedFramework.framework/FBSharedFramework")
    print(f"  3. Search for specific symbols:")
    print(f"     python3 tools/strings_grep.py {fw_dir}/FBSharedFramework.framework/FBSharedFramework Sponsor")

if __name__ == '__main__':
    main()

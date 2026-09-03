#!/usr/bin/env python3
"""
Quick class analysis - extract key methods for multiple classes at once.
"""
import subprocess

def quick_analyze(binary_path, class_name):
    """Use strings to find method signatures for a class."""
    result = subprocess.run(
        ['strings', binary_path],
        capture_output=True,
        text=True,
        timeout=60
    )

    lines = result.stdout.split('\n')

    # Find lines that look like method type encodings for this class
    # Format: T@"ClassName",...method_name
    methods = set()

    for line in lines:
        if class_name in line and len(line) < 200:
            # Check if it looks like a method signature
            if 'T@"' in line and class_name in line:
                # Extract method name (last part after comma, before newline)
                parts = line.split(',')
                if len(parts) >= 2:
                    method_name = parts[-1].strip()
                    if method_name and len(method_name) < 80:
                        methods.add(method_name)

    return sorted(methods)

def main():
    binary = '/tmp/fb_extract/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework'

    classes = [
        'FBVideoPlaybackContainerView',
        'FBVideoPlaybackController',
        'FBVideoPlaybackItem',
        'FBSnacksMediaContainerView',
        'FBSnacksNewVideoView',
        'FBShortsSideBarView',
        'FBShortsPlaybackController',
        'FBVideoOverlayPluginComponentBackgroundView',
        'FBSnacksMediaPlayerManager',
        'FBVideoOverlayPluginComponentView'
    ]

    for class_name in classes:
        print(f"\n{'=' * 80}")
        print(f"📦 {class_name}")
        print('=' * 80)

        methods = quick_analyze(binary, class_name)

        if methods:
            print(f"Methods ({len(methods)}):")
            for method in methods[:30]:
                print(f"  - {method}")
            if len(methods) > 30:
                print(f"  ... and {len(methods) - 30} more")
        else:
            print("  (no methods found)")

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Parse Mach-O binary to extract ObjC class information.
Extracts class names, methods, and ivars directly from binary structure.
"""
import sys
import struct
from macholib.MachO import MachO
from macholib.mach_o import LC_SEGMENT, LC_SEGMENT_64

def read_string_at_offset(data, offset):
    """Read null-terminated string at offset."""
    end = data.find(b'\x00', offset)
    if end < 0:
        return ""
    return data[offset:end].decode('utf-8', errors='ignore')

def extract_objc_info(binary_path):
    """Extract ObjC class information from Mach-O binary."""
    with open(binary_path, 'rb') as f:
        data = f.read()

    # Find all occurrences of class names
    target_classes = [
        b'FBVideoPlaybackContainerView',
        b'FBVideoPlaybackController',
        b'FBVideoPlaybackItem',
        b'FBSnacksMediaContainerView',
        b'FBSnacksNewVideoView',
        b'FBShortsSideBarView',
        b'FBShortsPlaybackController',
        b'FBVideoOverlayPluginComponentBackgroundView',
        b'FBSnacksMediaPlayerManager'
    ]

    results = {}

    for target in target_classes:
        class_name = target.decode('utf-8')
        results[class_name] = {'methods': set(), 'ivars': set()}

        # Find all occurrences of the class name
        offset = 0
        while True:
            idx = data.find(target, offset)
            if idx < 0:
                break

            # Look for method names near this class reference
            # Search 1000 bytes before and after
            search_start = max(0, idx - 5000)
            search_end = min(len(data), idx + 5000)
            region = data[search_start:search_end]

            # Look for method selectors (usually null-terminated strings)
            # Common pattern: method name followed by null byte
            for method_candidate in [b'init', b'dealloc', b'viewDidLoad', b'viewWillAppear',
                                     b'viewDidAppear', b'layoutSubviews', b'initWithFrame',
                                     b'currentVideoPlaybackItem', b'setVideoItem',
                                     b'setPlaying', b'HDPlaybackURL', b'SDPlaybackURL',
                                     b'controller', b'videoPlaybackController',
                                     b'setVideoPlayer', b'setPlaybackController',
                                     b'configureWithVideo', b'configureWithModel',
                                     b'manager', b'currentItem', b'playbackItem',
                                     b'initWithThread', b'initWithCoder']:

                method_offset = 0
                while True:
                    m_idx = region.find(method_candidate, method_offset)
                    if m_idx < 0:
                        break

                    # Check if it's a null-terminated string
                    actual_pos = search_start + m_idx
                    if actual_pos + len(method_candidate) < len(data):
                        if data[actual_pos + len(method_candidate)] == 0:
                            # Valid string
                            # Extract full method name (read until null)
                            full_name = read_string_at_offset(data, actual_pos)
                            if full_name and len(full_name) < 100:
                                results[class_name]['methods'].add(full_name)

                    method_offset = m_idx + 1

            offset = idx + len(target)

    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 parse_macho.py <binary>")
        sys.exit(1)

    binary_path = sys.argv[1]
    print(f"🔍 Parsing {binary_path}")
    print("=" * 80)

    results = extract_objc_info(binary_path)

    for class_name, info in results.items():
        print(f"\n📦 {class_name}")
        print(f"  Methods found: {len(info['methods'])}")
        if info['methods']:
            for method in sorted(info['methods'])[:20]:  # First 20
                print(f"    - {method}")
            if len(info['methods']) > 20:
                print(f"    ... and {len(info['methods']) - 20} more")

        print(f"  Ivars found: {len(info['ivars'])}")
        if info['ivars']:
            for ivar in sorted(info['ivars'])[:20]:  # First 20
                print(f"    - _{ivar}")

if __name__ == '__main__':
    main()

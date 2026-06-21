#!/usr/bin/env python3
"""
dump_objc.py - Dump ObjC class/method/ivar info from iOS Mach-O binaries.

Works around LC_DYLD_CHAINED_FIXUPS limitations of standard class-dump tools.
Handles iOS 15+ binaries with pre-rebased pointers.

KNOWN LIMITATION: This script is best-effort. For iOS 15+ binaries with
LC_DYLD_CHAINED_FIXUPS, some pointers use different slide prefixes (e.g.
0x10000 for class list, 0x40000 for class_ro_t data), making full parsing
difficult. For best results, use the runtime verifier (Tweak.x) approach
or class-dump-ios on macOS.

For more reliable analysis, see: tools/INVESTIGATION_GUIDE.md

Usage:
    python3 dump_objc.py <binary> [filter]
    python3 dump_objc.py /path/to/Facebook > headers.txt
    python3 dump_objc.py /path/to/FBSharedFramework FBFeedUnit > feedunit.txt
    python3 dump_objc.py /path/to/binary "*asFBFeedUnitIsSponsoredGraphQL"
"""
import sys
import struct

def parse_macho(b):
    """Parse Mach-O header and return segments, sections, and base_vmaddr."""
    magic = struct.unpack_from('<I', b, 0)[0]
    if magic != 0xfeedfacf:
        raise ValueError(f"Only 64-bit Mach-O supported (magic=0x{magic:x})")

    ncmds = struct.unpack_from('<I', b, 16)[0]
    segments = []
    sections = []
    base_vmaddr = 0  # Default
    off = 32
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', b, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = b[off+8:off+24].rstrip(b'\x00').decode()
            vmaddr = struct.unpack_from('<Q', b, off+24)[0]
            vmsize = struct.unpack_from('<Q', b, off+32)[0]
            fileoff = struct.unpack_from('<Q', b, off+40)[0]
            filesize = struct.unpack_from('<Q', b, off+48)[0]
            # First segment's vmaddr is the base
            if segname == '__TEXT' and base_vmaddr == 0:
                base_vmaddr = vmaddr
            segments.append({'name': segname, 'vmaddr': vmaddr, 'vmsize': vmsize,
                            'fileoff': fileoff, 'filesize': filesize})
            nsects = struct.unpack_from('<I', b, off+64)[0]
            sect_off = off + 72
            for j in range(nsects):
                sectname = b[sect_off:sect_off+16].rstrip(b'\x00').decode()
                ssegname = b[sect_off+16:sect_off+32].rstrip(b'\x00').decode()
                saddr = struct.unpack_from('<Q', b, sect_off+32)[0]
                ssize = struct.unpack_from('<Q', b, sect_off+40)[0]
                soff = struct.unpack_from('<I', b, sect_off+48)[0]
                full = f"{ssegname}.{sectname}"
                sections.append({
                    'name': full, 'vmaddr': saddr, 'vmsize': ssize,
                    'size': ssize, 'off': soff
                })
                sect_off += 80
        off += cmdsize
    return segments, sections, base_vmaddr

def find_classlist(sections):
    """Find __objc_classlist section."""
    for s in sections:
        if s['name'] == '__DATA_CONST.__objc_classlist' or s['name'] == '__DATA.__objc_classlist':
            return s
    return None

def try_resolve_ptr(b, sections, ptr):
    """Try to resolve pointer as file offset. Try multiple interpretations."""
    if ptr == 0 or ptr >= len(b):
        return None

    # Try as direct file offset
    if ptr < len(b):
        # Quick sanity check: see if there's a string nearby
        try:
            if 32 <= b[ptr] < 127 and 32 <= b[ptr+1] < 127 and 32 <= b[ptr+2] < 127:
                # Might be valid string
                return ptr
        except IndexError:
            pass

    # Try stripping various slide prefixes
    for mask in [0x0000FFFFFFFFFFFF, 0x00000000FFFFFFFF, 0x0000000000FFFFFF]:
        m = ptr & mask
        if 0 < m < len(b) - 4:
            try:
                if 32 <= b[m] < 127:
                    return m
            except IndexError:
                pass

    return None

def vm_to_file_offset(segments, sections, vmaddr, base_vmaddr=0):
    """Convert vmaddr (with slide) to file offset.

    If vmaddr is in __DATA_CONST section (pre-rebased), strip the slide
    and use the section's (off, size) range.

    Otherwise compute file offset using vmaddr - base_vmaddr.
    """
    # First, try if it's a direct section address (vmaddr matches a section)
    for s in sections:
        if s['vmaddr'] <= vmaddr < s['vmaddr'] + s['size']:
            return s['off'] + (vmaddr - s['vmaddr'])

    # Try stripping high bits and checking against sections
    for mask in [0x0000FFFFFFFFFFFF, 0x00000000FFFFFFFF, 0x0000000000FFFFFF]:
        m = vmaddr & mask
        for s in sections:
            if s['vmaddr'] <= m < s['vmaddr'] + s['size']:
                return s['off'] + (m - s['vmaddr'])

    # If base_vmaddr is set, try vmaddr - base_vmaddr
    if base_vmaddr > 0:
        fo = vmaddr - base_vmaddr
        if 0 <= fo < len(b):
            return fo

    return None

def read_class(b, cls_ptr, segments=None, sections=None, base_vmaddr=0):
    """Read class_t at cls_ptr. Return (name, methods, ivars) or None."""
    if cls_ptr == 0:
        return None

    # Convert cls_ptr to file offset
    if segments is not None:
        fo = vm_to_file_offset(segments, sections, cls_ptr, base_vmaddr)
    else:
        fo = cls_ptr  # Assume already a file offset
    if fo is None or fo >= len(b) - 40:
        return None

    # class_t: isa(8) super(8) cache(8) vtable(8) data(8)
    data_ptr_raw = struct.unpack_from('<Q', b, fo + 32)[0]
    if data_ptr_raw == 0:
        return None

    # Convert data_ptr
    if segments is not None:
        data_ptr = vm_to_file_offset(segments, sections, data_ptr_raw, base_vmaddr)
    else:
        data_ptr = data_ptr_raw
    if data_ptr is None or data_ptr >= len(b) - 72:
        return None

    # class_ro_t: flags(4) instStart(4) instSize(4) reserved(4)
    #              ivarLayout(8) name(8) baseMethods(8) baseProtocols(8)
    #              ivars(8) weakIvarLayout(8) baseProperties(8)
    name_ptr_raw = struct.unpack_from('<Q', b, data_ptr + 24)[0]
    methods_ptr_raw = struct.unpack_from('<Q', b, data_ptr + 32)[0]
    ivars_ptr_raw = struct.unpack_from('<Q', b, data_ptr + 48)[0]

    # Read class name
    name = None
    if segments is not None:
        name_fo = vm_to_file_offset(segments, sections, name_ptr_raw, base_vmaddr)
    else:
        name_fo = name_ptr_raw
    if name_fo and 0 < name_fo < len(b) - 1:
        try:
            end = b.find(b'\x00', name_fo)
            if end > 0 and end - name_fo < 200 and end - name_fo > 2:
                candidate = b[name_fo:end].decode('utf-8', errors='replace')
                if candidate[0].isupper() and candidate.isprintable():
                    name = candidate
        except (UnicodeDecodeError, IndexError):
            pass

    if not name:
        return None

    # Read methods
    methods = []
    if segments is not None:
        methods_ptr = vm_to_file_offset(segments, sections, methods_ptr_raw, base_vmaddr)
    else:
        methods_ptr = methods_ptr_raw
    if methods_ptr and 0 < methods_ptr < len(b) - 8:
        try:
            flags, count = struct.unpack_from('<II', b, methods_ptr)
            if 0 < count < 500:
                is_relative = (flags & 0x3) == 0x3
                moff = methods_ptr + 8
                for k in range(min(count, 500)):
                    if is_relative:
                        if moff + 8 > len(b): break
                        name_rel = struct.unpack_from('<i', b, moff)[0]
                        m_name_fo = methods_ptr + 8 + k * 12 + name_rel
                        if 0 < m_name_fo < len(b) - 1:
                            me = b.find(b'\x00', m_name_fo)
                            if me > 0 and me - m_name_fo < 200:
                                methods.append(b[m_name_fo:me].decode('utf-8', errors='replace'))
                        moff += 12
                    else:
                        if moff + 8 > len(b): break
                        m_name_fo_raw = struct.unpack_from('<Q', b, moff)[0]
                        m_name_fo = vm_to_file_offset(segments, sections, m_name_fo_raw, base_vmaddr) if segments else m_name_fo_raw
                        if m_name_fo and 0 < m_name_fo < len(b) - 1:
                            me = b.find(b'\x00', m_name_fo)
                            if me > 0 and me - m_name_fo < 200:
                                methods.append(b[m_name_fo:me].decode('utf-8', errors='replace'))
                        moff += 24
        except (struct.error, IndexError):
            pass

    # Read ivars
    ivars = []
    if segments is not None:
        ivars_ptr = vm_to_file_offset(segments, sections, ivars_ptr_raw, base_vmaddr)
    else:
        ivars_ptr = ivars_ptr_raw
    if ivars_ptr and 0 < ivars_ptr < len(b) - 8:
        try:
            entsize, count = struct.unpack_from('<II', b, ivars_ptr)
            if 0 < count < 200:
                ivar_off = ivars_ptr + 8
                for k in range(min(count, 200)):
                    if ivar_off + 24 > len(b): break
                    iv_offset, iv_name_fo_raw, iv_type_fo = struct.unpack_from('<QQQ', b, ivar_off)
                    iv_name_fo = vm_to_file_offset(segments, sections, iv_name_fo_raw, base_vmaddr) if segments else iv_name_fo_raw
                    if iv_name_fo and 0 < iv_name_fo < len(b) - 1:
                        ie = b.find(b'\x00', iv_name_fo)
                        if ie > 0 and ie - iv_name_fo < 200:
                            ivars.append(b[iv_name_fo:ie].decode('utf-8', errors='replace'))
                    ivar_off += 32
        except (struct.error, IndexError):
            pass

    return (name, methods, ivars)

def main():
    if len(sys.argv) < 2:
        print("Usage: dump_objc.py <binary> [filter]")
        print("\nExamples:")
        print("  python3 dump_objc.py Facebook")
        print("  python3 dump_objc.py FBSharedFramework FBFeedUnit")
        print("  python3 dump_objc.py FBSharedFramework \"*asFBFeedUnitIsSponsoredGraphQL\"")
        sys.exit(1)

    path = sys.argv[1]
    filter_str = sys.argv[2] if len(sys.argv) > 2 else None

    with open(path, 'rb') as f:
        b = f.read()

    try:
        segments, sections, base_vmaddr = parse_macho(b)
    except Exception as e:
        print(f"Error parsing binary: {e}", file=sys.stderr)
        sys.exit(1)

    classlist = find_classlist(sections)
    if not classlist:
        print("No __objc_classlist found", file=sys.stderr)
        sys.exit(1)

    n_classes = classlist['size'] // 8
    print(f"=== ObjC Dump: {path} ===", file=sys.stderr)
    print(f"Total classes: {n_classes}", file=sys.stderr)
    print(f"Base vmaddr: 0x{base_vmaddr:x}", file=sys.stderr)
    print(f"NOTE: iOS 15+ binaries with LC_DYLD_CHAINED_FIXUPS may have parsing issues.", file=sys.stderr)
    print(f"      For best results, use runtime verifier (Tweak.x) approach.\n", file=sys.stderr)

    if filter_str:
        if '*' in filter_str:
            # Method search
            target = filter_str.replace('*', '')
            print(f"=== Classes with method matching '{target}' ===\n")
            matches = []
            for i in range(n_classes):
                cls_ptr = struct.unpack_from('<Q', b, classlist['off'] + i*8)[0]
                info = read_class(b, cls_ptr, segments, sections, base_vmaddr)
                if info is None: continue
                name, methods, ivars = info
                if target in methods:
                    matches.append(info)
            for name, methods, ivars in matches:
                print(f"@interface {name}")
                for m in methods:
                    marker = " [T]" if m == target else "    "
                    print(f"  {marker} {m}")
                print()
            print(f"Total: {len(matches)} matches")
        else:
            # Name search
            print(f"=== Classes with '{filter_str}' in name ===\n")
            matches = []
            for i in range(n_classes):
                cls_ptr = struct.unpack_from('<Q', b, classlist['off'] + i*8)[0]
                info = read_class(b, cls_ptr, segments, sections, base_vmaddr)
                if info is None: continue
                if filter_str in info[0]:
                    matches.append(info)
            for info in matches:
                name, methods, ivars = info
                print(f"@interface {name}")
                for m in methods:
                    print(f"    {m}")
                for iv in ivars:
                    print(f"  ivar: {iv}")
                print()
            print(f"Total: {len(matches)} matches")
    else:
        # Full dump (limited to first 50)
        print("=== All classes (first 50) ===\n")
        count = 0
        for i in range(n_classes):
            if count >= 50: break
            cls_ptr = struct.unpack_from('<Q', b, classlist['off'] + i*8)[0]
            info = read_class(b, cls_ptr, segments, sections, base_vmaddr)
            if info is None: continue
            name, methods, ivars = info
            print(f"@interface {name}  // {len(methods)} methods, {len(ivars)} ivars")
            count += 1
        if n_classes > 50:
            print(f"\n... and {n_classes - 50} more classes")
            print("(use filter to narrow down)")

if __name__ == '__main__':
    main()

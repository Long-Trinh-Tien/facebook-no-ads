#!/usr/bin/env python3
"""
dump_objc.py - Dump ObjC class/method/ivar info from iOS Mach-O binaries.

Works around LC_DYLD_CHAINED_FIXUPS limitations of standard class-dump tools.
Handles iOS 15+ binaries with pre-rebased pointers (high bits like 0x1000000).

Usage:
    python3 dump_objc.py <binary> [filter]
    python3 dump_objc.py /path/to/Facebook > headers.txt
    python3 dump_objc.py /path/to/FBSharedFramework FBFeedUnit > feedunit.txt

Output: List of all ObjC classes with methods + ivars (if filter matches).
"""
import sys
import struct

def vm_to_file(sections, vmaddr):
    for s in sections:
        if s['addr'] <= vmaddr < s['addr'] + s['size']:
            return s['off'] + (vmaddr - s['addr'])
    return None

def read_string(b, off):
    if off < 0 or off >= len(b):
        return None
    end = b.find(b'\x00', off)
    if end < 0:
        return None
    return b[off:end].decode('utf-8', errors='replace')

def parse_macho(b):
    """Parse Mach-O header, return list of sections."""
    magic = struct.unpack_from('<I', b, 0)[0]
    if magic != 0xfeedfacf:
        raise ValueError(f"Only 64-bit Mach-O supported (magic=0x{magic:x})")

    ncmds = struct.unpack_from('<I', b, 16)[0]
    sections = []
    off = 32
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', b, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack_from('<I', b, off+64)[0]
            sect_off = off + 72
            for j in range(nsects):
                sectname = b[sect_off:sect_off+16].rstrip(b'\x00').decode()
                ssegname = b[sect_off+16:sect_off+32].rstrip(b'\x00').decode()
                saddr = struct.unpack_from('<Q', b, sect_off+32)[0]
                ssize = struct.unpack_from('<Q', b, sect_off+40)[0]
                soff = struct.unpack_from('<I', b, sect_off+48)[0]
                sections.append({
                    'name': f"{ssegname}.{sectname}",
                    'addr': saddr, 'size': ssize, 'off': soff
                })
                sect_off += 80
        off += cmdsize
    return sections

def strip_slide(val):
    """Strip pre-rebased high bits (0x10000, 0x40000, etc.) from pointer."""
    # Try different masks
    for mask in [0x0000FFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]:
        masked = val & mask
        if 0 < masked < 0x10000000000:  # reasonable vmaddr
            return masked
    return val

def read_class(b, sections, cls_ptr):
    """Read class_t at cls_ptr. Return (name, methods, ivars) or None."""
    fo = vm_to_file(sections, strip_slide(cls_ptr))
    if fo is None or fo + 40 > len(b):
        return None

    # class_t: isa(8) super(8) cache(8) vtable(8) data(8)
    data_ptr_raw = struct.unpack_from('<Q', b, fo + 32)[0]
    data_ptr = strip_slide(data_ptr_raw)
    fo2 = vm_to_file(sections, data_ptr)
    if fo2 is None or fo2 + 72 > len(b):
        return None

    # class_ro_t: flags(4) instStart(4) instSize(4) reserved(4)
    #              ivarLayout(8) name(8) baseMethods(8) baseProtocols(8)
    #              ivars(8) weakIvarLayout(8) baseProperties(8)
    name_ptr = strip_slide(struct.unpack_from('<Q', b, fo2 + 24)[0])
    methods_ptr = strip_slide(struct.unpack_from('<Q', b, fo2 + 32)[0])
    ivars_ptr = strip_slide(struct.unpack_from('<Q', b, fo2 + 48)[0])

    # Read class name
    name = None
    name_fo = vm_to_file(sections, name_ptr)
    if name_fo:
        name = read_string(b, name_fo)

    # Read methods
    methods = []
    if methods_ptr:
        mfo = vm_to_file(sections, methods_ptr)
        if mfo:
            flags, count = struct.unpack_from('<II', b, mfo)
            is_relative = (flags & 3) == 3
            method_off = mfo + 8
            for k in range(min(count, 500)):
                if is_relative:
                    if method_off + 8 > len(b): break
                    name_rel = struct.unpack_from('<i', b, method_off)[0]
                    m_name_vm = methods_ptr + 8 + k * 12 + name_rel
                    mn_fo = vm_to_file(sections, m_name_vm)
                    if mn_fo:
                        mname = read_string(b, mn_fo)
                        if mname:
                            methods.append(mname)
                    method_off += 12
                else:
                    if method_off + 8 > len(b): break
                    m_name_vm = strip_slide(struct.unpack_from('<Q', b, method_off)[0])
                    mn_fo = vm_to_file(sections, m_name_vm)
                    if mn_fo:
                        mname = read_string(b, mn_fo)
                        if mname:
                            methods.append(mname)
                    method_off += 24

    # Read ivars
    ivars = []
    if ivars_ptr:
        ifo = vm_to_file(sections, ivars_ptr)
        if ifo:
            entsize, count = struct.unpack_from('<II', b, ifo)
            ivar_off = ifo + 8
            for k in range(min(count, 200)):
                if ivar_off + 24 > len(b): break
                iv_offset, iv_name_vm, iv_type_vm = struct.unpack_from('<QQQ', b, ivar_off)
                in_fo = vm_to_file(sections, strip_slide(iv_name_vm))
                if in_fo:
                    iname = read_string(b, in_fo)
                    if iname:
                        ivars.append(iname)
                ivar_off += 32

    return (name, methods, ivars) if name else None

def find_class_with_method(b, sections, classlist, target_method):
    """Find all classes that have a method matching target_method."""
    matches = []
    for cls_ptr in classlist:
        info = read_class(b, sections, cls_ptr)
        if info is None: continue
        name, methods, ivars = info
        if target_method in methods:
            matches.append((name, methods))
    return matches

def search_by_pattern(b, sections, classlist, pattern):
    """Search class names for substring pattern."""
    matches = []
    for cls_ptr in classlist:
        info = read_class(b, sections, cls_ptr)
        if info is None: continue
        name, methods, ivars = info
        if pattern in name:
            matches.append(name)
    return matches

def main():
    if len(sys.argv) < 2:
        print("Usage: dump_objc.py <binary> [filter]")
        print("Examples:")
        print("  python3 dump_objc.py Facebook")
        print("  python3 dump_objc.py FBSharedFramework FBFeedUnit")
        sys.exit(1)

    path = sys.argv[1]
    filter_str = sys.argv[2] if len(sys.argv) > 2 else None

    with open(path, 'rb') as f:
        b = f.read()

    try:
        sections = parse_macho(b)
    except Exception as e:
        print(f"Error parsing binary: {e}", file=sys.stderr)
        sys.exit(1)

    classlist = None
    for s in sections:
        if s['name'] == '__DATA_CONST.__objc_classlist':
            classlist = s
            break

    if not classlist:
        print("No __objc_classlist found", file=sys.stderr)
        sys.exit(1)

    n_classes = classlist['size'] // 8
    cls_ptrs = []
    for i in range(n_classes):
        ptr = strip_slide(struct.unpack_from('<Q', b, classlist['off'] + i*8)[0])
        if ptr > 0:
            cls_ptrs.append(ptr)

    print(f"=== ObjC Dump: {path} ===")
    print(f"Total classes: {len(cls_ptrs)}\n")

    if filter_str:
        # Filter mode: show only matching classes
        if '*' in filter_str:
            # Method search
            target = filter_str.replace('*', '')
            print(f"=== Classes with method matching '{target}' ===\n")
            matches = find_class_with_method(b, sections, cls_ptrs, target)
            for name, methods in matches:
                print(f"@interface {name}")
                for m in methods:
                    marker = " [T]" if m == target else "    "
                    print(f"  {marker} {m}")
                print()
            print(f"Total: {len(matches)} matches")
        else:
            # Name search
            print(f"=== Classes with '{filter_str}' in name ===\n")
            matches = search_by_pattern(b, sections, cls_ptrs, filter_str)
            for name in matches:
                info = None
                for cls_ptr in cls_ptrs:
                    info = read_class(b, sections, cls_ptr)
                    if info and info[0] == name:
                        break
                if info:
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
        for i, cls_ptr in enumerate(cls_ptrs[:50]):
            info = read_class(b, sections, cls_ptr)
            if info is None: continue
            name, methods, ivars = info
            print(f"@interface {name}  // {len(methods)} methods, {len(ivars)} ivars")
        if len(cls_ptrs) > 50:
            print(f"\n... and {len(cls_ptrs) - 50} more classes")
            print("(use filter to narrow down)")

if __name__ == '__main__':
    main()

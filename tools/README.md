# RE Tools — Custom Python Scripts

> Python scripts do tụi mình viết để work-around các limitations của tools có sẵn.
> Đặc biệt hữu ích cho iOS 15+ binaries với `LC_DYLD_CHAINED_FIXUPS` mà class-dump cũ không xử lý được.

## Tools

### 1. `dump_objc.py` — Dump ObjC class/method/ivar info

**Vấn đề giải quyết:** `class-dump` (nygard) không work với iOS 15+ binaries do `LC_DYLD_CHAINED_FIXUPS`. `lechium/classdumpios` cần macOS để build.

**Solution:** Custom parser handle pre-rebased pointers (high bits 0x10000, 0x40000) mà không cần macOS.

**Usage:**
```bash
# List all classes (first 50)
python3 dump_objc.py /path/to/binary

# Filter by class name
python3 dump_objc.py /path/to/binary FBFeedUnit

# Find classes with specific method (use * prefix)
python3 dump_objc.py /path/to/binary "*asFBFeedUnitIsSponsoredGraphQL"

# Save to file
python3 dump_objc.py /path/to/binary FBFeedUnit > feedunit_headers.txt
```

**Output example:**
```
=== ObjC Dump: FBSharedFramework ===
Total classes: 22297

=== Classes with 'FBMemNewsFeedEdge' in name ===

@interface FBMemNewsFeedEdge

Total: 1 matches
```

---

### 2. `binary_diff.py` — Compare 2 binary dumps

**Vấn đề giải quyết:** Khi FB update, cần biết classes/methods nào thay đổi để update tweak.

**Usage:**
```bash
# 1. Dump 2 versions
python3 dump_objc.py old/FBSharedFramework > old_dump.txt
python3 dump_objc.py new/FBSharedFramework > new_dump.txt

# 2. Compare
python3 binary_diff.py old_dump.txt new_dump.txt
```

**Output example:**
```
=== Binary Diff ===
Old: 22297 classes
New: 22300 classes

=== REMOVED CLASSES (2) ===
  - FBMemFeedStory
  - FBVideoChannelPlaylistItem

=== ADDED CLASSES (5) ===
  + FBMemNewFeedUnit
  + FBNewAdType
  ...

=== METHOD CHANGES (3 classes) ===

  FBMemNewsFeedEdge:
    - initWithFBTree:
    + node
    + deduplicationKey
    + category

=== SUMMARY ===
Removed: 2 classes
Added: 5 classes
Modified: 3 classes (method/ivar)
```

---

### 3. `strings_grep.py` — Smart string search

**Vấn đề giải quyết:** Raw `strings | grep` returns too much noise. Cần filter theo type (class name, method name).

**Usage:**
```bash
# All matches
python3 strings_grep.py /path/to/binary Sponsor

# Only class names
python3 strings_grep.py /path/to/binary Sponsor --type=class

# Only method names
python3 strings_grep.py /path/to/binary asFB --type=method

# Custom min length and limit
python3 strings_grep.py /path/to/binary Snacks --min-len 5 --limit 50
```

**Output:**
```
Searching FBSharedFramework for 'Snacks' (type=all)

Found 23 matches (showing first 23):

  [C] FBSnacksBucketsSeenStateManager
  [C] FBSnacksMediaContainerView
  [C] FBSnacksPhotoView
  [C] FBSnacksWebPhotoView
  [C] FBSnacksNewVideoView
  [M] initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:
  [M] _sendSeenThreadIDsWithBucket:session:
  ...
```

---

### 4. `extract_ipa.py` — Extract and analyze IPA

**Vấn đề giải quyết:** Manual `unzip + find binary + read plist` is repetitive.

**Usage:**
```bash
python3 extract_ipa.py /path/to/facebook.ipa
# or
python3 extract_ipa.py /path/to/facebook.ipa my_work_dir
```

**Output example:**
```
Extracting facebook.ipa → my_work_dir/...
App: my_work_dir/Payload/Facebook.app

=== App Info ===
  Bundle ID: com.facebook.Facebook6
  Name: Facebook
  Display Name: Facebook
  Version: 560.1.0
  Build: 555107060
  Min iOS: 15.1
  Executable: Facebook

=== Main Binary ===
  Path: my_work_dir/Payload/Facebook.app/Facebook
  Size: 10.7 MB
  Arch: arm64 (Mach-O 64-bit)

=== Frameworks (54) ===
  FBSharedFramework.framework (83.6 MB)
  FBAuthenticationFramework.framework (5.1 MB)
  ...

=== Next steps ===
  1. Class dump main binary:
     python3 tools/dump_objc.py my_work_dir/Payload/Facebook.app/Facebook
  ...
```

---

## Workflow Example

Phân tích FB 561.0.0 sau khi update (chưa có tweak):

```bash
# Step 1: Get IPA from App Store (or test version)
ls ~/Downloads/facebook_561.ipa

# Step 2: Extract and get info
python3 tools/extract_ipa.py ~/Downloads/facebook_561.ipa fb561
# → Get Bundle ID, version, frameworks list

# Step 3: Compare with last known version
mkdir -p ~/glow-snapshots
python3 tools/extract_ipa.py ~/glow-snapshots/560.0/facebook.ipa fb560
python3 tools/dump_objc.py fb560/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework FBFeedUnit > fb560_feedunit.txt
python3 tools/dump_objc.py fb561/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework FBFeedUnit > fb561_feedunit.txt
python3 tools/binary_diff.py fb560_feedunit.txt fb561_feedunit.txt
# → See what changed

# Step 4: Search for new symbols
python3 tools/strings_grep.py fb561/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework Sponsor

# Step 5: Update Tweak.x based on findings
# (See UPDATE_GUIDE.md for full workflow)

# Step 6: Build and test
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i ~/Downloads/facebook_561.ipa -o glow_v7.ipa -f ./packages/...deb --overwrite -s -d
```

---

## Why Custom Tools?

**Standard tools have issues with iOS 15+:**

| Tool | Issue | Workaround |
|------|-------|-----------|
| `class-dump` (nygard) | No iOS 15+ chained fixups support | Use `dump_objc.py` |
| `class-dump-z` | Same as above | Same |
| `leak-classdumpios` | macOS only | Use `dump_objc.py` on Linux |
| `otool` (Apple) | macOS only | Use `objdump` or `r2` |
| `leak-jtool` | macOS only | Build from source or use `r2` |
| `frida` | Needs jailbreak | Use custom runtime tracer |
| `FLEX` | View actions crash | Use `dump_objc.py` for static |

**These custom tools work on Linux + handle iOS 15+ binaries.**

---

## Python Requirements

```bash
pip3 install --break-system-packages \
    lief \  # Optional - for additional Mach-O parsing
    capstone \  # Optional - for disassembly
```

Built-in `struct` and `plistlib` are enough for basic usage.

---

## Compatibility

- **Python:** 3.6+
- **OS:** Linux, macOS, WSL
- **iOS binary versions:** 12+ (including 15+ with chained fixups)
- **Architectures:** arm64, arm64e (some pointers may be stripped incorrectly)

---

## See Also

- [TOOLS_INSTALL.md](../TOOLS_INSTALL.md) — Install standard RE tools
- [INVESTIGATION_GUIDE.md](../INVESTIGATION_GUIDE.md) — Full RE methodology
- [UPDATE_GUIDE.md](../UPDATE_GUIDE.md) — How to update tweak for new FB versions
- [BUILD_GUIDE.md](../BUILD_GUIDE.md) — How to build the tweak

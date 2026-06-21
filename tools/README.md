# RE Tools — Custom Python Scripts

> ⚠️ **IMPORTANT:** For iOS 15+ binaries with `LC_DYLD_CHAINED_FIXUPS`, these tools have
> **LIMITED RELIABILITY**. Different pointers use different slide prefixes (0x10000, 0x40000, 0x5118001, etc.),
> making full static parsing difficult without a proper Mach-O library.
>
> **RECOMMENDED:** Use the **runtime verifier** (`glow_verify.ipa` from R3.0-verify) for
> reliable class/method discovery. The Python tools are useful for quick checks and
> string searches.

## Tools

### 1. `dump_objc.py` — Dump ObjC class/method/ivar info (partial)

**Vấn đề giải quyết:** `class-dump` (nygard) không work với iOS 15+ binaries do `LC_DYLD_CHAINED_FIXUPS`. `lechium/classdumpios` cần macOS.

**Solution:** Custom parser với multiple slide prefix handling.

**Usage:**
```bash
# List all classes (first 50)
python3 dump_objc.py /path/to/binary

# Filter by class name
python3 dump_objc.py /path/to/binary FBFeedUnit

# Find classes with specific method (use * prefix)
python3 dump_objc.py /path/to/binary "*asFBFeedUnitIsSponsoredGraphQL"
```

**Limitations:**
- iOS 15+ binaries may have classes with names that don't show in dump
- Methods/ivars may be incomplete
- For best results, use runtime verifier

**Best Use Case:** Quick check if a class/method exists, search for keywords.

---

### 2. `binary_diff.py` — Compare 2 binary dumps (works if dumps are valid)

**Vấn đề giải quyết:** Khi FB update, cần biết classes/methods nào thay đổi.

**Usage:**
```bash
# 1. Get dumps (use runtime verifier for best results)
#    Or if you have valid dump_objc output:
python3 dump_objc.py old/FBSharedFramework > old.txt
python3 dump_objc.py new/FBSharedFramework > new.txt

# 2. Compare
python3 binary_diff.py old.txt new.txt
```

**Output example:**
```
=== Binary Diff ===
Old: 22297 classes
New: 22300 classes

=== REMOVED CLASSES (2) ===
  - FBMemFeedStory
  - FBVideoChannelPlaylistItem

=== SUMMARY ===
Removed: 2 classes
Added: 5 classes
Modified: 3 classes
```

---

### 3. `strings_grep.py` — Smart string search (RECOMMENDED — works well)

**Vấn đề giải quyết:** Raw `strings | grep` returns too much noise. Cần filter theo type.

**Usage:**
```bash
# All matches
python3 strings_grep.py /path/to/binary Sponsor

# Only class names
python3 strings_grep.py /path/to/binary Sponsor --type=class

# Only method names
python3 strings_grep.py /path/to/binary asFB --type=method
```

**Output:**
```
Searching FBSharedFramework for 'Snacks' (type=all)

Found 23 matches (showing first 23):

  [C] FBSnacksBucketsSeenStateManager
  [C] FBSnacksMediaContainerView
  [C] FBSnacksPhotoView
  [C] FBSnacksWebPhotoView
  [M] initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:
  [M] _sendSeenThreadIDsWithBucket:session:
  ...
```

**Why this works:** Just searches ASCII strings, doesn't need pointer resolution.

---

### 4. `extract_ipa.py` — Extract and analyze IPA (RECOMMENDED — works well)

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
  Bundle ID: com.facebook.Facebook
  Name: Facebook
  Version: 560.1.0
  Build: 963085760
  Min iOS: 15.1

=== Frameworks (10) ===
  FBCameraFramework.framework (63.3 MB)
  ...
```

---

## Recommended Workflow

For FB 560.x binaries (iOS 15+), the recommended approach is:

```
1. EXTRACT (extract_ipa.py)         → Get binary, version, frameworks
       ↓
2. STATIC SEARCH (strings_grep.py)  → Find class/method names
       ↓
3. STATIC DUMP (dump_objc.py)        → Best-effort class/method list
       ↓
4. RUNTIME VERIFY (Tweak.x)          → DEFINITIVE answer
       ↓
5. BUILD TWEAK based on verified APIs
```

For other binaries (older iOS, different apps), the tools may work fully.

---

## Why Custom Tools Don't Fully Work for iOS 15+

The iOS 15+ `LC_DYLD_CHAINED_FIXUPS` feature uses different slide prefixes for different data:

| Data type | Common slide prefix |
|-----------|---------------------|
| `__objc_classlist` entries | `0x10000` |
| `class_ro_t` data | `0x40000` |
| `class_ro_t` name | `0x5118001000000` (varies!) |
| Method list | `0x20000` |
| String pointers (in `__objc_methname`) | `0x10000` |

A proper Mach-O library (lief, macholib) should handle these, but they fail on iOS 15+ chained fixups.

**Solution:** Use the **runtime verifier** (Tweak.x that lists classes at runtime) for definitive results. The runtime already resolves all pointers correctly because ObjC runtime knows the load address.

---

## Tools Status Summary

| Tool | Status | Use case |
|------|--------|----------|
| `dump_objc.py` | ⚠️ Partial | Quick check (incomplete for iOS 15+) |
| `binary_diff.py` | ✅ Works if dumps valid | Compare 2 dumps |
| `strings_grep.py` | ✅ Works well | Search symbols |
| `extract_ipa.py` | ✅ Works well | Extract + info |

---

## Best Alternative: Runtime Verifier

For definitive class/method discovery on iOS 15+ binaries, use the runtime verifier built earlier:

**Source:** `glow-verify/Tweak.x` (in `~/test/glow/glow-verify/`)
**IPA:** `~/test/glow/glow_verify.ipa`
**Output:** `/var/mobile/Documents/glow_verify.txt`

This Tweak runs in the actual app context, so all pointers resolve correctly. Used to discover:
- FBMemNewsFeedEdge (3 methods: node, deduplicationKey, category)
- FBSnacksBucketsSeenStateManager (6 methods, including _sendSeenThreadIDsWithBucket:session:)
- FBSnacksMediaContainerView (17 methods)
- FBVideoOverlayPluginComponentBackgroundView (8 methods)
- 13+ other target classes verified

See `BUILD_GUIDE.md` and `INVESTIGATION_GUIDE.md` for full details.

---

## Python Requirements

```bash
pip3 install --break-system-packages lief
```

Built-in `struct` and `plistlib` are enough for basic usage.

---

## Compatibility

- **Python:** 3.6+
- **OS:** Linux, macOS, WSL
- **iOS binary versions:** 12-14 (fully), 15+ (partial — strings_grep + extract_ipa work)
- **Architectures:** arm64, arm64e

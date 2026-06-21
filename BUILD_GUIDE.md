# Build & Test Guide — Glow Clone for Facebook 560.x

> Hướng dẫn build từ source, inject vào Facebook IPA, install lên device.

---

## Prerequisites

- Linux/macOS với `clang` (iOS toolchain)
- `Theos` ở `/home/tommy/theos/` (hoặc path khác)
- iOS SDK 16.5+ (`/home/tommy/theos/sdks/iPhoneOS16.5.sdk/`)
- Facebook IPA đã decrypt (cần thiết bị jailbreak để decrypt, hoặc download từ trusted source)
- `cyan` tool để inject dylib
- `TrollStore` trên device iOS 16+

---

## Quick Start

```bash
# 1. Build tweak
cd /home/tommy/test/glow/glow-from-source
THEOS=/home/tommy/theos make package FINALPACKAGE=1

# 2. Copy deb
cp packages/com.tommy.glowv3_1.0.0_iphoneos-arm.deb /home/tommy/test/glow/glowv7.deb

# 3. Inject into Facebook IPA
cyan -i /home/tommy/test/glow/facebook.ipa \
     -o /home/tommy/test/glow/glow_v7.ipa \
     -f /home/tommy/test/glow/glowv7.deb \
     --overwrite -s -d

# 4. Install via TrollStore
# AirDrop glow_v7.ipa to device → Open in TrollStore → Install
```

---

## Step-by-step

### 1. Setup Theos

```bash
# Install Theos (if not already)
git clone --recursive https://github.com/theos/theos.git ~/theos

# Verify SDK
ls ~/theos/sdks/
# Should show: iPhoneOS12.4.sdk, iPhoneOS16.5.sdk, etc.
```

### 2. Get Decrypted Facebook IPA

**Option A: Decrypt from device (jailbreak)**
```bash
# Use frida or dumpdecrypted on jailbroken device
# Output: /var/containers/Bundle/Application/.../Facebook.app/Facebook
```

**Option B: Download decrypted**
- Find trusted source online (Apple binary signed)
- Verify with `codesign -dvv Facebook.app/Facebook`

### 3. Build Tweak

```bash
cd /home/tommy/test/glow/glow-from-source
THEOS=/home/tommy/theos make package FINALPACKAGE=1
```

**Output:** `packages/com.tommy.glowv3_1.0.0_iphoneos-arm.deb`

**Troubleshooting:**
- `Error: missing iOS SDK` → check `ls $THEOS/sdks/`
- `Error: arm64e vs arm64` → check `Makefile` ARCHS=arm64
- `Warning as error` → already handled with `-Wno-error=deprecated-declarations`

### 4. Inject into IPA

```bash
cyan -i /path/to/facebook.ipa \
     -o /path/to/output.ipa \
     -f /path/to/tweak.deb \
     --overwrite -s -d
```

**Options:**
- `-i` input IPA
- `-o` output IPA
- `-f` tweak deb file
- `--overwrite` overwrite output
- `-s` sign with adhoc
- `-d` debug mode

### 5. Install via TrollStore

1. AirDrop `glow_v7.ipa` to device
2. Open TrollStore → `+` icon → Select IPA
3. Wait for install
4. Open Facebook app

### 6. Verify Working

After opening Facebook, check `/var/mobile/Documents/glow.txt`:

```bash
# Use Files app on device, or ssh/afc to copy
# Or open in any text editor that can access /var/mobile/Documents
```

**Expected log content:**
```
=== Glow R3.5/v7 — <date> ===
[ctor] viewDidAppear hook installed

=== Installing hooks (R3.5/v7) ===
  hook #0: FBMemNewsFeedEdge.node -> nil for SPONSORED
  hook #1: cellForItem
  hook #2: willDisplay
  hook #3: _sendSeenThreadIDsWithBucket:session: -> no-op
  hook #4: _sendThreadIDsAsSeenInViewerSession: -> no-op
  hook #5: markThreadsView... -> no-op
=== Done ===
[seen] blocked _sendSeenThreadIDsWithBucket (count=1)
...
```

**Verify visually:**
- ✅ Ads are hidden in news feed (no empty gaps)
- ✅ Story seen does NOT register (check story tray of friend)
- ✅ Feed scroll smooth

---

## Project Structure

```
glow-from-source/
├── Tweak.x                 # Main source (R3.5/v7)
├── Makefile                # Theos build config
├── GlowV3.plist            # Filter for Facebook bundle IDs
├── control                 # Package metadata
├── packages/               # Built .deb files
└── INVESTIGATION_GUIDE.md  # Teaching file

glow-v3/                    # Alternative build dir
└── Tweak.x                 # Same code as above
```

---

## Tweak.x Source Overview

### Hooked Classes

| Class | Method | Action |
|-------|--------|--------|
| `FBMemNewsFeedEdge` | `node` | Return nil for SPONSORED |
| `FBComponentCollectionViewDataSource` | `cellForItemAtIndexPath:` | Hide ad cell (backup) |
| `FBComponentCollectionViewDataSource` | `willDisplayCell:forItemAtIndexPath:` | Hide ad cell (backup) |
| `FBSnacksBucketsSeenStateManager` | `_sendSeenThreadIDsWithBucket:session:` | No-op (network) |
| `FBSnacksBucketsSeenStateManager` | `_sendThreadIDsAsSeenInViewerSession:` | No-op (local) |
| `FBSnacksBucketsSeenStateManager` | `markThreadsViewReceiptsAndLightweightReactionsAsSeen:...` | No-op (high-level) |

### Ad Detection Logic

```c
BOOL isAdEdge(id memEdge) {
    NSString *cat = [memEdge category];
    if ([cat isEqualToString:@"SPONSORED"]) return YES;
    if ([cat isEqualToString:@"AD"]) return YES;
    if ([cat isEqualToString:@"IN_STREAM_AD"]) return YES;
    return NO;
}
```

### Categories Encountered

| Category | Type | Hide? |
|----------|------|-------|
| ORGANIC | Regular posts | No |
| ENGAGEMENT | Suggested posts | No |
| FB_SHORTS | Reels | No |
| MULTI_FB_STORIES_TRAY | Stories tray | No |
| SPONSORED | **Ads** | **Yes** |
| AD | **Ads** | **Yes** |
| IN_STREAM_AD | **In-stream ads** | **Yes** |

---

## Makefile Details

```makefile
TWEAK_NAME = GlowV3
GlowV3_FILES = Tweak.x
GlowV3_FRAMEWORKS = UIKit
GlowV3_CFLAGS = -fobjc-arc -Wno-error
```

- `ARCHS = arm64` (default for modern iOS)
- `TARGET_IPHONEOS_DEPLOYMENT_VERSION = 12.0`
- `THEOS_PACKAGE_SCHEME = rootful` (default)

---

## Customizing

### Add More Hooks

Edit `Tweak.x`, add to `installHooks()`:

```c
@try {
    Class newCls = objc_getClass("YourClassName");
    if (newCls) {
        SEL sel = sel_registerName("yourMethod:");
        Method m = class_getInstanceMethod(newCls, sel);
        if (m) {
            IMP orig = method_getImplementation(m);
            method_setImplementation(m, (IMP)yourHook);
            LOG("  hook: yourMethod:\n");
        }
    }
} @catch (...) {}
```

### Change Log File

In `glow_init()`:
```c
snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/yourfile.txt", home);
```

### Filter Bundle IDs

Edit `GlowV3.plist`:
```xml
<dict>
    <key>Filter</key>
    <dict>
        <key>Bundles</key>
        <array>
            <string>com.facebook.Facebook</string>
            <string>com.facebook.Facebook6</string>
        </array>
    </dict>
</dict>
```

---

## Troubleshooting

### Build fails: `fatal error: 'UIKit/UIKit.h' file not found`
```bash
# Check SDK
ls $THEOS/sdks/iPhoneOS16.5.sdk/System/Library/Frameworks/UIKit.framework/Headers/
# If missing, install or symlink
```

### App crashes immediately on launch
- Check `/var/mobile/Documents/glow.txt` for hook install errors
- Verify all hooked classes exist in current FB version
- Check device crash log (Settings → Privacy → Analytics → Analytics Data)

### Ads not blocked
- Check log: `node` hook should fire `[node] blocked SPONSORED edge (count=N)`
- If count=0, the `category` method may not be called or returns wrong value
- Try different FB version (560.x tested)

### Story seen not blocked
- Open a story
- Check log: should see `[seen] blocked ... (count=N)`
- If count=0, story seen path may be different in current FB version
- Search binary for `FBSnacksBucketsSeenStateManager` to confirm class still exists

### No log file created
- Constructor might have crashed
- Check device crash log
- Try simpler test tweak (just write log) to verify tweak is loaded

---

## Other Tools

### FLEXLoader (browse classes at runtime)

Already built at `/home/tommy/test/glow/glow_flex.ipa` (FLEX + Facebook).
Use to explore classes in current FB version.

⚠️ FLEX view actions may crash on complex FB classes.

### Verifier (dump classes/methods)

Already built at `/home/tommy/test/glow/glow_verify.ipa`.
Outputs class list to `/var/mobile/Documents/glow_verify.txt`.

---

## Versioning

| FB Version | Status | Known Issues |
|------------|--------|--------------|
| 560.x | ✅ Works | None known |
| 561+ | ⚠️ Unknown | Need to re-verify classes |
| <560 | ❌ Untested | Different API |

---

## License

Private project. Not for distribution.

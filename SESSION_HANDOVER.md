# Glow v8 — Session Handover (v8.0 → v8.2.13)

> **Status:** Core working (ad block + story seen). Reels download WIP.
> **Branch:** `v8-glow-framework`
> **Latest build:** `glow_v8.ipa` (v1.2.13, 195MB)
> **Log path:** `/var/mobile/Documents/glow.txt`

---

## 1. Quick Start (Next Session)

```bash
# Build
cd /tmp/facebook-no-ads
THEOS=/home/tommy/theos make package FINALPACKAGE=1
# /tmp/facebook-no-ads/packages/com.tommy.glowv3_1.2.13_iphoneos-arm.deb

# Inject (requires facebook.ipa in /home/tommy/test/glow/)
cyan -i /home/tommy/test/glow/facebook.ipa -o /tmp/glow_v8.ipa \
    -f packages/com.tommy.glowv3_1.2.13_iphoneos-arm.deb --overwrite -s -d

# Copy to working dir (for TrollStore sideload)
cp /tmp/glow_v8.ipa /home/tommy/test/glow/glow_v8.ipa

# Commit and push
git add -A && git commit -m "..." && git push origin v8-glow-framework
```

**IMPORTANT: filename MUST stay `glow_v8.ipa` (user requirement).**

---

## 2. Working Features (in v1.2.13)

| # | Feature | Hook | Verified |
|---|---------|------|----------|
| 0 | Ad block | `FBMemNewsFeedEdge.node` returns nil for SPONSORED/AD/IN_STREAM_AD/PROMOTION | ✅ |
| 1 | Cell hiding | `FBComponentCollectionViewDataSource.collectionView:cellForItemAtIndexPath:` | ✅ |
| 2 | Cell willDisplay | same class, willDisplay | ✅ |
| 3-5 | Story seen | `FBSnacksBucketsSeenStateManager` 3 paths → no-op | ✅ |
| 6 | Settings long press | viewDidAppear → walk views, add UILongPressGestureRecognizer | ✅ |
| 7 | Hide composer | `FBNewsFeedViewController.viewDidLoad` → set `_shouldHideComposer=YES` | ✅ |
| 8 | Download story (long press) | `FBSnacksMediaContainerView` new init + didMoveToWindow → add long press | ✅ |
| 9 | Download video (long press) | `FBVideoOverlayPluginComponentBackgroundView.didLongPress:` | ✅ for in-feed video |
| 10 | Reels download (button) | Hook `FBVideoHomeUnifiedPlayerViewController.viewWillAppear:` → add button | ⚠️ WIP |

**Settings (12 toggles in GlowSettingsViewController):**
- Default ON: `removeAds`, `disableStorySeen`
- Default OFF: `downloadVideo`, `downloadStory`, `removePYMK`, `removeReelsCarousel`, `removeSuggested`, `hideComposer`, `disableAutoNext`, `confirmLike`, `downloadReels`, `hideOverlay`, `confirmReelsLike`, `downloadLongPress`, `markAsSeen`, `removeStoryPYMK`, `allFormats`, `clearCacheOnLaunch`, `notifyUpdates`
- **BUG FIXED in v1.2.3**: Reels section was hardcoded to `@NO` → now uses `@(s_*Var)` so toggles persist

**File structure:** `analysis/` folder has:
- `analysis/glow-original/` — original Glow 1.3.1 deobfuscation + comparison
- `analysis/r4-verifier/` — runtime class discovery tool (Tweak_R4.x)
- `analysis/v8-PLAN.md` — original v8.2 plan

---

## 3. Critical Files

| File | Purpose |
|------|---------|
| `/tmp/facebook-no-ads/Tweak.x` | **Main source** (1726 lines, all hooks) |
| `/tmp/facebook-no-ads/Makefile` | Build config (GlowV3, arm64+arm64e+armv7) |
| `/tmp/facebook-no-ads/control` | Package metadata, bump version here |
| `/tmp/facebook-no-ads/GlowV3.plist` | Filter: `com.facebook.Facebook` + `com.facebook.Facebook6` |
| `/home/tommy/test/glow/glow_v8.ipa` | **Latest sideload** (v1.2.13) |
| `/home/tommy/test/facebook-no-ads/Tweak.x` | Working dir copy (sync after build) |
| `/home/tommy/test/glow/glow_r4.ipa` | R4 verifier (for class discovery) |

**Git remote:** `https://github.com/Long-Trinh-Tien/facebook-no-ads.git`
- branch `v8-glow-framework` — main dev
- branch `r4-verifier` — runtime verifier
- branch `analysis/glow-original` — original Glow 1.3.1 analysis

---

## 4. Reels Download — Current WIP (CRITICAL!)

### User feedback
- **v1.2.10**: button không hiện → bug cast `self` thành `UIView` thay vì `UIViewController`
- **v1.2.11**: hook `viewWillAppear:` thay `viewDidLoad` (vì viewDidLoad fire trước khi lazy install có thể fire)
- **v1.2.12**: hook ALL Reels classes, không chỉ class đầu tiên xuất hiện
- **v1.2.13 (latest)**: button **HIỆN** nhưng **SAI LAYER** — bị che bởi view khác. Khi user mở comment/share thì button mới lộ ra. Tap không work vì button không nhận touch.

### Classes discovered (từ R4 + user log)
```
FBVideoHomeViewController                (container, NSKVONotifying_)
FBVideoHomeUnifiedPlayerViewController  (actual player, has video)
FBVideoHomeFeedSurfaceViewController    (feed surface)
FBSurfaceViewControllerImpl             (surface impl)
FBPSUnifiedShareSheetViewController     (share sheet)
FBNotificationsViewController
```

### Current code (in `hooked_reelsViewWillAppear`)
- Hook TẤT CẢ classes matching "FBVideoHome*" or "FBReel*"
- Replace `viewWillAppear:` IMP on class + superclass
- Add button at `W-66, H-280` (bottom-right)
- Set `zPosition = 9999`, walk up + bringSubviewToFront
- ALSO add separate button to keyWindow with `zPosition = 99999`

### Known issues to fix in v1.2.14+
1. **Button bị che bởi layer khác** — zPosition chưa đủ, cần hook `bringSubviewToFront` của view cover
2. **Tap không work** — button có thể bị view khác (action buttons column) consume touch. Cần disable user interaction của các view xung quanh
3. **Button biến mất sau khi scroll Reel** — cần hook lại viewWillAppear: mỗi lần

### Possible approaches to try
1. **Add button to a NEW UIWindow** với `windowLevel = UIWindowLevelAlert + 1` → luôn trên cùng
2. **Find like button class** via tap log (already implemented in v1.2.11), use like button's parent as anchor
3. **Hook `viewDidAppear:`** thay vì `viewWillAppear:` — fire sau khi view đã hoàn toàn layout
4. **Find correct view to add button** — walk subviews, find specific action button column, add as sibling

### Tap-to-discover (already in code)
Khi user tap bất kỳ trong Reels, log sẽ có:
```
[reels/tap] class=Foo frame=(...)
[reels/tap]   +0 Foo
[reels/tap]   +1 Bar (parent)
...
```
Gửi log này cho user để biết class thật của like button.

---

## 5. Hook Architecture (Quick Reference)

### 5.1 Lazy install pattern
- `viewDidAppear:` hook (global) detects when class is loaded
- Strip `NSKVONotifying_` prefix
- Install hook on actual class via `method_setImplementation`
- For Reels: also hook on superclass to catch KVO subclass

### 5.2 Cast pattern
```objc
// In viewDidLoad/viewWillAppear/etc:
UIView *v = nil;
if ([self isKindOfClass:[UIViewController class]]) {
    v = [(UIViewController *)self view];  // ← correct
} else if ([self isKindOfClass:[UIView class]]) {
    v = (UIView *)self;
}
if (!v) return;
```
**DON'T:** `UIView *v = (UIView *)self;` (self is VC, not View)

### 5.3 C function type encoding
```objc
typedef id (*FnType)(id, SEL, id, id, id, id, id, BOOL);
FnType fn = (FnType)(uintptr_t)orig;
result = fn(self, _cmd, thread, bucket, delegate, generator, toolbox, shouldBlurMedia);
```

### 5.4 Logging
- All logs go to `/var/mobile/Documents/glow.txt`
- Format: `LOG("...%s\n", str.UTF8String)` (use %s + UTF8String, not %@)
- Flush at end of session, not per line (perf)

---

## 6. FB Class Reference (verified in 560.x)

| Class | Methods we hook | Status |
|-------|-----------------|--------|
| `FBMemNewsFeedEdge` | `node` | ✅ confirmed |
| `FBMemModelObject` | `initWithFBPandoTree:` (exist, not used) | confirmed |
| `FBSnacksBucketsSeenStateManager` | 3 paths | ✅ |
| `FBComponentCollectionViewDataSource` | `cellForItem`, `willDisplay` | ✅ |
| `FBNewsFeedViewController` | `viewDidLoad` → set _shouldHideComposer | ✅ |
| `FBNewsFeedViewControllerConfiguration` | has `_shouldHideComposer` ivar | ✅ |
| `FBSnacksMediaContainerView` | NEW init: `initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:` | ✅ |
| `FBSnacksNewVideoView` | `.manager` → `.currentVideoPlaybackItem` | ✅ |
| `FBSnacksPhotoView` | → `_photoView` (FBSnacksWebPhotoView) → `_photoView` (FBWebPhotoView) → `.photo` | ⚠️ imageSpecifier KVO fail |
| `FBWebImageNetworkSpecifier` | `.allInfoURLsSortedByDescImageFlag` | ✅ |
| `FBVideoPlaybackItem` | `HDPlaybackURL`, `SDPlaybackURL`, `isSponsored` | ✅ |
| `FBVideoOverlayPluginComponentBackgroundView` | `didLongPress:` | ✅ |
| `FBVideoHomeViewController` | `viewWillAppear:` | ⚠️ WIP |
| `FBVideoHomeUnifiedPlayerViewController` | `viewWillAppear:` | ⚠️ WIP |
| `FBMemFeedStory` | REMOVED (GraphQL stub only) | ❌ |
| `FBVideoChannelPlaylistItem` | REMOVED | ❌ |
| `FBMemSuggestedForYouEdge` | REMOVED | ❌ |
| `FBMemPeopleYouMayKnowEdge` | EXISTS but 0 methods, only class check works | ⚠️ |
| `FBMemPhoto` | EXISTS but no `imageSpecifier` (KVC fail) | ❌ photo story broken |

### Categories seen in feed (verified)
- `ORGANIC` — normal post
- `ENGAGEMENT` — likes/comments reminders
- `SPONSORED` — ads (blocked)
- `AD` — ads (blocked)
- `IN_STREAM_AD` — ads (blocked)
- `PROMOTION` — ads (blocked, added in v1.2.4)
- `FB_SHORTS` — embedded Reels
- `MULTI_FB_STORIES_TRAY` — story tray header (in section 0/1, skipped)
- `PROMOTION` — promotional posts (also blocked)

---

## 7. Testing Workflow

1. **Build v1.2.X**:
   ```bash
   cd /tmp/facebook-no-ads
   sed -i 's/Version: 1.2.X/Version: 1.2.Y/' control
   sed -i 's/v8.2.X/v8.2.Y/' Tweak.x  # in the LOG line
   rm -rf .theos/ packages/
   THEOS=/home/tommy/theos make package FINALPACKAGE=1
   cyan -i /home/tommy/test/glow/facebook.ipa -o /tmp/glow_v8.ipa -f packages/com.tommy.glowv3_1.2.Y_iphoneos-arm.deb --overwrite -s -d
   cp /tmp/glow_v8.ipa /home/tommy/test/glow/glow_v8.ipa
   ```

2. **User test cycle**:
   - Remove app, install new `glow_v8.ipa`
   - Check log `/var/mobile/Documents/glow.txt`
   - Verify version header matches (e.g. `=== Glow v8.2.Y ===`)
   - Test features, report back

3. **Versioning rule**: bump on every commit (1.2.1 → 1.2.2 → ...) to force dylib reload on device

---

## 8. Open Questions / TODOs

| Item | Priority | Notes |
|------|----------|-------|
| Reels download button z-order | 🔴 HIGH | v1.2.13 partial — button shows but wrong layer, tap doesn't work |
| Photo story download | 🟡 MED | `imageSpecifier` KVC fails on `FBMemPhoto` — need to find correct path |
| Hide PYMK | 🟡 MED | Class check works but PYMK might not show as feed edge (try after fix Reels) |
| Hide Suggested | 🟡 MED | `FBMemSuggestedForYouEdge` REMOVED — find another way |
| Hide Reels carousel | 🟠 LOW | Class unknown, needs R&D |
| Localize to all 11 languages | 🟠 LOW | vi.lproj from Glow 1.3.1 ready to copy |
| Onboarding screen (WelcomeVC) | ⚪ NICE | Optional, v8.3+ |
| Update checker | ⚪ NICE | Optional, v8.3+ |

---

## 9. Quick Debugging Tips

### If hook doesn't fire
- Check log for `LAZY hook installed` or `HOOKED viewWillAppear` 
- If missing → class name in substring match is wrong
- If present but no `ADDED BUTTON` → hook not firing on that class instance (likely KVO wrapper)

### If button added but not visible
- Check `layer.zPosition` — must be > other views
- Check `bringSubviewToFront` called on all ancestors
- Consider adding to keyWindow with zPosition = max
- Consider `window.windowLevel = UIWindowLevelAlert + 1`

### If button visible but tap doesn't work
- Other view's gesture recognizer consuming tap
- Try `cancelsTouchesInView = NO` on all gesture recognizers
- Try setting `userInteractionEnabled = NO` on overlapping views
- Or add button to a separate window

### If hook crashes
- Check method signature: `class_getInstanceMethod(cls, sel)` returns NULL if method doesn't exist
- Check class exists: `objc_getClass(name)` returns NULL if not loaded
- Check args match: `FnType` must match exact arg count and types
- Wrap in `@try/@catch` to log exceptions

---

## 10. Build/Deploy Cheat Sheet

```bash
# === Build ===
cd /tmp/facebook-no-ads
rm -rf .theos/ packages/
THEOS=/home/tommy/theos make package FINALPACKAGE=1

# === Output ===
ls packages/
# com.tommy.glowv3_1.2.X_iphoneos-arm.deb

# === Inject into IPA ===
cyan -i /home/tommy/test/glow/facebook.ipa \
    -o /tmp/glow_v8.ipa \
    -f packages/com.tommy.glowv3_1.2.X_iphoneos-arm.deb \
    --overwrite -s -d

# === Copy to working dir ===
cp /tmp/glow_v8.ipa /home/tommy/test/glow/glow_v8.ipa
cp /tmp/facebook-no-ads/Tweak.x /home/tommy/test/facebook-no-ads/Tweak.x

# === Git commit ===
cd /tmp/facebook-no-ads
git add -A
git -c user.name="opencode" -c user.email="opencode@ai.local" commit -m "..."
git push origin v8-glow-framework

# === User tests via TrollStore ===
# 1. Long press Facebook app icon → Remove → Delete
# 2. Open TrollStore → Install glow_v8.ipa
# 3. Open Facebook, check log at /var/mobile/Documents/glow.txt
```

---

## 11. Files Modified Per Version (for git log)

| Version | Date | Key change |
|---------|------|------------|
| v8.0 (1.0.0) | 06-12 | Initial: ad block + story seen |
| v8.0.1 | 06-15 | Polish: settings UI (English) |
| v8.0.2 | 06-15 | i18n Vietnamese |
| v8.0.3 | 06-15 | Modal sheet UI, fixed toggle bug |
| v8.2.0 | 06-21 | Hook #7 #8 #9: Hide Composer, Download Story (init), Download Video |
| v8.2.1 | 06-21 | Hide Composer, Download Story (init) |
| v8.2.2 | 06-21 | didMoveToWindow hook (fix story crash) |
| v8.2.3 | 06-21 | UI bug fix (Reels hardcoded @NO), progress+haptic |
| v8.2.4 | 06-21 | Toast (non-modal), add PROMOTION to blacklist |
| v8.2.5 | 06-21 | Reels class discovery (VC log + view walk) |
| v8.2.6 | 06-21 | Hook #10: Reels download via FBVideoHomeUnifiedPlayerViewController |
| v8.2.7 | 06-21 | Reels button overlay (replaces long press) |
| v8.2.8 | 06-21 | Lazy install Reels hook on viewDidAppear |
| v8.2.9 | 06-21 | Reels button with delay + screen bounds fallback |
| v8.2.10 (1.2.10) | 06-21 | **CRITICAL FIX**: cast self as UIViewController to get .view |
| v8.2.11 | 06-21 | Hook viewWillAppear + tap-to-discover |
| v8.2.12 | 06-21 | Hook ALL Reels classes (not just first) |
| v8.2.13 | 06-21 | zPosition + keyWindow button (WIP - button in wrong layer) |
| **v8.2.14 (TODO)** | - | Fix button z-order properly, find like button class |

---

## 12. Hints for Next Session

1. **Read this doc first** (SESSION_HANDOVER.md)
2. **Check current state**: `cd /tmp/facebook-no-ads && git log --oneline -10`
3. **Read latest Tweak.x** to see current hooks
4. **Read user feedback** in chat — they test on real device, send back log
5. **Always check log first** before adding new hooks — `[reels/tap] class=...` reveals view hierarchy
6. **Don't change filename** — always `glow_v8.ipa`
7. **Bump version on every commit** — `1.2.X` in `control`, `v8.2.Y` in Tweak.x LOG line
8. **If button issue**: try add to NEW UIWindow with `windowLevel = UIWindowLevelAlert + 1`
9. **Photo story KVO fail**: try class `FBWebImageMemorySpecifier` directly, or look for photo URLs in `FBMemPhoto` ivars
10. **Don't commit binaries** — `.gitignore` already excludes `.dylib`, `.deb`, `.ipa`

---

**Last updated:** 2026-06-21 15:43 UTC (v1.2.13)
**Status:** Core ✅ | Reels WIP | Other features pending

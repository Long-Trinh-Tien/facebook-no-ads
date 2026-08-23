# Glow Clone — Compact Session Summary
> **Last updated**: 2026-06-21 17:05 UTC (v8.2.17)
> **Target**: iOS 16+, Facebook 560.1.0 arm64, TrollStore sideload
> **Status**: Core (ad block, story seen) ✅ | Reels download WIP

---

## 🎯 Core Features Working (v8.2.17)

| # | Feature | Hook | Status |
|---|---------|------|--------|
| 0 | Ad block (home feed) | `FBMemNewsFeedEdge.node` returns nil for SPONSORED/AD/IN_STREAM_AD/PROMOTION | ✅ |
| 1 | Cell hiding | `FBComponentCollectionViewDataSource.collectionView:cellForItemAtIndexPath:` | ✅ |
| 2 | Cell willDisplay | same class, willDisplay | ✅ |
| 3 | Story seen | `FBSnacksBucketsSeenStateManager.markThreadsViewReceiptsAndLightweightReactionsAsSeen:` | ✅ |
| 4 | Story seen | same class, `_markThreadAsSeen:` | ✅ |
| 5 | Story seen | same class, `_sendSeenThreadIDsWithBucket:` | ✅ |
| 6 | Settings long press | `UIViewController.viewDidAppear:` → walk views, add UILongPressGestureRecognizer | ✅ |
| 7 | Hide composer | `FBNewsFeedViewController.viewDidLoad` → set `_shouldHideComposer=YES` | ✅ |
| 8 | Download story (long press) | `FBSnacksMediaContainerView` (new init + didMoveToWindow) → UILongPress | ✅ |
| 9 | Download video (long press) | `FBVideoOverlayPluginComponentBackgroundView.didLongPress:` | ✅ in-feed only |
| 10 | Reels download | `FBVideoHomeUnifiedPlayerViewController.viewDidLoad` | ✅ legacy |
| **11** | **Reels download (v8.2.16)** | `FBShortsSideBarView.layoutSubviews` → add button as child | ✅ |

---

## 🏗️ Architecture

### 3-Layer Anti-Versioning (Glow-original style)
- **Layer 1**: UIKit entry points (`viewDidLoad`, `viewDidAppear:`)
- **Layer 2**: Walk view tree, check class names
- **Layer 3**: respondsToSelector checks + lazy hook install

### 11 Hooks (most recent first)
1. FBMemNewsFeedEdge.node (model layer filter)
2. FBComponentCollectionViewDataSource cellForItem + willDisplay (collection view)
3. FBSnacksBucketsSeenStateManager 3 paths (story)
4. UIViewController.viewDidAppear (settings + lazy install)
5. FBNewsFeedViewController.viewDidLoad (composer hide)
6. FBSnacksMediaContainerView init + didMoveToWindow (story download)
7. FBVideoOverlayPluginComponentBackgroundView.didLongPress (video download)
8. FBVideoHomeUnifiedPlayerViewController.viewDidLoad (Reels, legacy)
9. **FBShortsSideBarView.layoutSubviews (v8.2.16+ - MAIN Reels download)**
10. UIView.viewWillDisappear on Reels VC (cleanup)
11. UIView.didAddSubview globally (R4 verifier only)

---

## 🎯 Reels Action Button Class Names (VERIFIED v8.2.17)

### Container
- **`FBShortsSideBarView`** (frame 360,0,**56,333** on screen 428 wide)

### Button classes (all `FDSTouchStateAnnouncingControl`)
- **Like**: label `"Nút Thích, nhấn đúp và giữ để hiển thị khay cảm xúc"`, frame (0,0,56,72)
- **Comment**: label `"Bình luận, 173 bình luận"`, frame (0,72,56,72)
- **Share**: label `"Chia sẻ, 137 lượt chia sẻ"`, frame (0,145,56,72)
- **Save**: label `"Lưu thước phim"`, frame (0,217,56,72)
- **More**: label `"Lựa chọn khác về thước phim này"`, frame (0,289,56,44)

### Full Reels hierarchy (verified by R4 v1.6 timed walks)
```
FBShortsViewerOverlayComponentView (overlay chính, full screen 428x848)
└── FBPassthroughView (content overlay 416x333, at +12,+12 from origin)
    ├── FBPassthroughView (author/follow section, 0,218,360,97)
    │   └── FDSTouchStateComponentView + FDSTouchStateAnnouncingControl "Tôi thấy"
    ├── FBPassthroughView (description, 0,86,372,0)
    ├── FBShortsDescriptionView (text)
    └── FBShortsSideBarView (360,0,56,333) ← RIGHT ACTION COLUMN ⭐
        ├── FDSTouchStateAnnouncingControl (0,0,56,72)    Like ⭐
        ├── FDSTouchStateAnnouncingControl (0,72,56,72)   Comment ⭐
        ├── FDSTouchStateAnnouncingControl (0,145,56,72)  Share ⭐
        ├── FDSTouchStateAnnouncingControl (0,217,56,72)  Save ⭐
        └── FDSTouchStateAnnouncingControl (0,289,56,44)  More ⭐
```

### Reels VC classes (4 of them)
1. `NSKVONotifying_FBVideoHomeViewController` → `FBVideoHomeViewController` (root container)
2. `FBVideoHomeUnifiedPlayerViewController` → `FBTrackableViewController` (player)
3. `FBVideoHomeFeedSurfaceViewController` (feed surface)
4. `FBSurfaceViewControllerImpl` (impl)

---

## 🔧 v8.2.17 — Reels button solution

### Hook
`FBShortsSideBarView.layoutSubviews` — fires every time the sidebar lays out (including when new Reel loaded).

### Filter (CRITICAL — added in v8.2.17)
`isInReelsContext()` walks superview chain. Returns NO if finds:
- `FBCommentStream` (comment sheet)
- `FBBottomSheet` (comment sheet)

Returns YES if finds:
- `FBShortsViewerOverlayComponentView` (Reels only)
- `FBVideoHomeUnifiedPlayerViewController` (Reels only)
- `FBVideoHomePassthroughView` (Reels only)

**Why needed**: FBShortsSideBarView exists in BOTH Reels AND comment sheets. Without filter, button appears in comment image attachments → crash when tapping.

### Button
- **Frame**: (8, -48, 40, 40) — above sidebar, canh giữa
- **Style**: Red circle, white border, ⬇ icon
- **zPosition**: 9999

### Cleanup
- `viewWillDisappear:` of Reels VC → remove button (v8.2.14+)
- Auto-cleanup when sidebar deallocates (subview auto-removed)

---

## 📁 Critical Files (for compact session)

| File | Status | Purpose |
|------|--------|---------|
| `/home/tommy/test/glow/glow_v8.ipa` | v1.2.17, 195MB | Main tweak (working) |
| `/home/tommy/test/glow/glow_r4.ipa` | v1.6.0, 195MB | Class discovery verifier |
| `/home/tommy/test/glow/facebook.ipa` | FB 560.1.0 arm64 | Base IPA |
| `/tmp/facebook-no-ads/Tweak.x` | 1985 lines | Main tweak source |
| `/tmp/facebook-no-ads/control` | v1.2.17 | Package metadata |
| `/tmp/facebook-no-ads/Makefile` | Tweak config | Build config |
| `/tmp/facebook-no-ads/GlowV3.plist` | Filter | `com.facebook.Facebook` + `com.facebook.Facebook6` |
| `/tmp/facebook-no-ads/analysis/r4-verifier/Tweak.x` | v1.6.0 | R4 verifier source |
| `/tmp/facebook-no-ads/SESSION_HANDOVER.md` | Outdated | Older handoff (replaced by this file) |

---

## 🏗️ Build Pipeline

```bash
cd /tmp/facebook-no-ads
rm -rf .theos/ packages/
THEOS=/home/tommy/theos make package FINALPACKAGE=1
# Output: packages/com.tommy.glowv3_<version>_iphoneos-arm.deb

cyan -i /home/tommy/test/glow/facebook.ipa -o /tmp/glow_v8.ipa \
    -f packages/com.tommy.glowv3_1.2.17_iphoneos-arm.deb \
    --overwrite -s -d

cp /tmp/glow_v8.ipa /home/tommy/test/glow/glow_v8.ipa
# Sideload via TrollStore
```

---

## 🐛 Crash History & Fixes

| Version | Cause | Fix | Status |
|---------|-------|-----|--------|
| R0 | addSubview: hook iOS 16+ | Removed | ✅ |
| R0 | objc_copyClassList in %ctor | Removed | ✅ |
| R1 | Timer scanner during login | Removed | ✅ |
| R1 | object_getIvar on C++ struct | Type-check | ✅ |
| R1 | aggressive chain walk | Removed | ✅ |
| R2 | objc_getClassList 10000+ crash | Filter FB prefix | ✅ |
| v8.2.16 | Button appears in comment sheet (FBShortsSideBarView exists there too) | v8.2.17: isInReelsContext() filter | ✅ |
| v8.2.16 | Crash when tapping comment image | Same fix | ✅ |

---

## 📋 FB Class Reference (verified 560.x)

### Critical classes (all FOUND, all hooks working)
- `FBMemNewsFeedEdge` (51 methods, has `node`/`category`/`deduplicationKey`)
- `FBMemModelObject` (GQLModel base)
- `FBSnacksBucketsSeenStateManager` (6 methods, 3 paths hooked)
- `FBComponentCollectionViewDataSource` (86 methods, 2 hooked)
- `FBNewsFeedViewController` (180 methods, has `_configuration`, `_componentCollectionViewDataSource`)
- `FBNewsFeedViewControllerConfiguration` (has `_shouldHideComposer` BOOL)
- `FBSnacksMediaContainerView` (init: thread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:)
- `FBSnacksNewVideoView` (has `manager` → `FBSnacksVideoManager.currentVideoPlaybackItem`)
- `FBSnacksPhotoView` (has `_photoView` → `FBSnacksWebPhotoView._photoView` → `FBWebPhotoView.photo` = `<FBWebPhotoViewFragment>`)
- `FBSnacksWebPhotoView` (has `_photoView`)
- `FBWebPhotoView` (has `photo`, `imageFlags`, `streamingConfigurator`)
- `FBWebImageNetworkSpecifier` (has `allInfoURLsSortedByDescImageFlag`)
- `FBWebImageMemorySpecifier` (has `image`, `url`)
- `FBVideoPlaybackItem` (has `HDPlaybackURL`, `SDPlaybackURL`, `isSponsored`, `isInStreamAd`)
- `FBVideoOverlayPluginComponentBackgroundView` (has `didLongPress:`, `_onSingleTapped:`, `_onDoubleTapped:`)
- `FBMemPeopleYouMayKnowEdge` (EXISTS, 0 methods — no working hide)

### Reels classes (verified by R4 + R3)
- `FBVideoHomeViewController` (root container)
- `FBVideoHomeUnifiedPlayerViewController` (player)
- `FBVideoHomeFeedSurfaceViewController` (feed)
- `FBSurfaceViewControllerImpl` (impl)
- **`FBShortsSideBarView`** (right action column — KEY for Reels download)
- `FBShortsViewerOverlayComponentView` (overlay)
- `FBShortsCustomHitTestView` (custom hit test)
- `FBShortsDescriptionView` (text description)

### Categories seen in feed
- `ORGANIC`, `ENGAGEMENT` (kept, not ads)
- `SPONSORED`, `AD`, `IN_STREAM_AD`, `PROMOTION` (blocked in v8.2.4+)
- `FB_SHORTS` (embedded Reels, kept)
- `MULTI_FB_STORIES_TRAY` (story tray, skipped)

---

## 🔍 R4 Verifier (Discovery Tool)

### `glow_r4.ipa` v1.6.0
- 4 hooks: `UIViewController.viewDidAppear:`, `UIView.layoutSubviews`, `UIView.didAddSubview:`, timer walks
- Outputs: `/var/mobile/Documents/glow_r4.txt`
- Also: Console.app (filter `GlowR4`)

### Usage
```bash
# Build
cd /tmp/facebook-no-ads/analysis/r4-verifier
rm -rf .theos/ packages/
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i /home/tommy/test/glow/facebook.ipa -o /tmp/glow_r4.ipa \
    -f packages/com.tommy.glowr4_1.6.0_iphoneos-arm.deb --overwrite -s -d
cp /tmp/glow_r4.ipa /home/tommy/test/glow/glow_r4.ipa
```

---

## 🐛 Known Issues / TODO

| Item | Priority | Notes |
|------|----------|-------|
| Reels button appearance in FB update | 🔴 HIGH | May need re-discover if FB renames class |
| Photo story download | 🟡 MED | `imageSpecifier` KVO fails on `FBMemPhoto` — need different path |
| Hide PYMK | 🟡 MED | `FBMemPeopleYouMayKnowEdge` exists but no working method |
| Hide Suggested | 🟡 MED | `FBMemSuggestedForYouEdge` REMOVED — need different way |
| Hide Reels carousel | 🟠 LOW | Class unknown, needs R&D |
| Localize to all 11 languages | 🟠 LOW | vi.lproj from Glow 1.3.1 ready to copy |
| Update checker | ⚪ NICE | Optional |

---

## 🔄 FB Update Strategy (for future)

If FB updates and breaks our hooks:

1. **Class name changed**:
   - Build R4 v1.6 → install → navigate → check log
   - Search for new class name in log
   - Update hook install code with new name

2. **Method signature changed**:
   - Use `class_getInstanceMethod(cls, sel)` returns NULL
   - LOG: `class NOT FOUND` or `method NOT FOUND`
   - Look for new selector via R4 walkSubviews

3. **View structure changed**:
   - R4 timed walks show empty FBShortsSideBarView
   - Walk subviews deeper
   - Find new container class

4. **Method swizzling blocked**:
   - Try `class_replaceMethod` (replaces vs sets)
   - Try `method_exchangeImplementations` (atomic swap)
   - Use `dispatch_once` for thread safety

5. **Crash on hook**:
   - `@try/@catch` around hook implementation
   - Log exception to file
   - Restore original implementation if possible

---

## 📊 Project Structure

```
/home/tommy/test/glow/
├── facebook.ipa              (base FB 560.1.0)
├── glow_v8.ipa               (main tweak, v1.2.17, 195MB)
├── glow_r4.ipa               (verifier, v1.6.0, 195MB)

/tmp/facebook-no-ads/
├── Tweak.x                    (main source, 1985 lines)
├── control                    (v1.2.17)
├── Makefile                   (build config)
├── GlowV3.plist               (filter)
├── V8_STATUS.md               (status doc)
├── SESSION_HANDOVER.md        (older handoff, now superseded)
├── COMPACT_SESSION.md         (this file)
├── packages/                  (build output)
├── .theos/                    (build artifacts)
├── analysis/
│   ├── glow-original/         (original Glow 1.3.1 analysis)
│   │   ├── COMPARISON.md
│   │   ├── haoict-source/
│   │   └── binary-analysis/
│   └── r4-verifier/
│       ├── Tweak.x            (v1.6.0)
│       ├── control
│       ├── Makefile
│       ├── GlowR4.plist
│       └── README.md
└── .git/                      (git repo)
```

---

## 🚀 Quick Start (after compact session)

```bash
# 1. Verify glow_v8.ipa exists
ls -la /home/tommy/test/glow/glow_v8.ipa
# Should show: 195386646 bytes (v1.2.17)

# 2. Test on device via TrollStore
# - Remove old app
# - Install glow_v8.ipa
# - Open FB → verify: no ads, story seen, settings, Reels download

# 3. If Reels download fails:
# - Install glow_r4.ipa (separate bundle ID)
# - Capture log: /var/mobile/Documents/glow_r4.txt
# - Compare FBShortsSideBarView structure to log above
# - Update Tweak.x with new class names

# 4. If photo story download fails:
# - Currently broken (FBMemPhoto has no imageSpecifier)
# - Try accessing photo via FBMemFeedStoryEdge instead

# 5. To build new version:
# - Edit Tweak.x
# - Bump version in control
# - cd /tmp/facebook-no-ads && make package
# - cyan inject
```

---

## 📝 Git Branches

- **`master`**: Original Glow 1.3.1 (closed source reference)
- **`r4-verifier`**: R4 class discovery tool
- **`analysis/glow-original`**: Decompiled Glow analysis
- **`v8-glow-framework`**: Main development (current) ✅

### Recent commits (v8-glow-framework)
```
f373ca7 v8.2.17: filter FBShortsSideBarView to Reels context only
9e31fe2 v8.2.16: hook FBShortsSideBarView.layoutSubviews (perfect alignment)
5104150 R4 v1.6: timed walks + didAddSubview hook + 7-level
e3aa729 R4 v1.5: 5-level walk + UIView.layoutSubviews hook + UIButton highlight
8d30878 R4 v1.4: NSLog + multi-path + fflush per call
f1b41ce R4 v1.3: replace class enum with subview walk (fix crash)
7d77a8e R4 v1.2: enumerate all FB classes + hook UIViewController
e1d1fcc v8.2.15: button added to FBVideoHomePassthroughView (right column)
```

---

## ✅ Done

- Ad block (4 categories)
- Story seen (3 paths)
- Settings UI (Vietnamese, modal sheet)
- Hide composer
- Download story (long press)
- Download video in feed (long press)
- Reels download button (v8.2.17, in correct position with Reels context filter)

## ⏳ TODO

- Reels download (verify in v8.2.17)
- Photo story download (broken)
- PYMK hide
- Suggested hide
- Reels carousel hide
- Localize to all 11 languages
- Onboarding screen
- Update checker

---

**Compact session ready for transfer.**
Next session: read COMPACT_SESSION.md, test v8.2.17, continue from there.

# v8 Status Document

> **Status**: v8.2.17 working (with Reels context filter)
> **Last update**: 2026-06-21 17:05 UTC

---

## What's Working

| Feature | Version | Verified |
|---------|---------|----------|
| Ad block (home feed) | v1.0.0+ | ✅ |
| Story seen (3 paths) | v1.0.0+ | ✅ |
| Settings UI (Vietnamese) | v1.0.0+ | ✅ |
| Hide composer | v1.0.0+ | ✅ |
| Download story (long press) | v1.0.0+ | ✅ |
| Download video (long press) | v1.0.0+ | ✅ in-feed only |
| Reels download button | v1.2.17 | ✅ verified |
| PROMOTION block | v1.2.4+ | ✅ |

## Reels Download — Current Implementation

### Hook (v8.2.16)
`FBShortsSideBarView.layoutSubviews` — fires when sidebar lays out (every Reel transition)

### Filter (v8.2.17)
`isInReelsContext()` walks superview chain:
- Returns YES if ancestor contains: `FBShortsViewerOverlayComponentView`, `FBVideoHomeUnifiedPlayerViewController`, `FBVideoHomePassthroughView`
- Returns NO if ancestor contains: `FBCommentStream`, `FBBottomSheet`
- **CRITICAL**: Without this filter, button appears in comment sheet (FBShortsSideBarView exists there too)

### Button
- **Frame**: (8, -48, 40, 40) — above sidebar, centered
- **Style**: Red circle, white border, ⬇ icon
- **zPosition**: 9999
- **Parent**: `FBShortsSideBarView` (same as Like/Comment/Share buttons)

## Changelog

| Version | Change |
|---------|--------|
| v1.0.0 | Initial: ad block + story seen |
| v1.0.0 | Add settings UI (English) |
| v1.0.0 | Vietnamese i18n |
| v1.0.0 | Modal sheet UI |
| v1.0.0 | Fix toggle bug |
| v1.0.0 | Add Reels hook (viewDidLoad) |
| v1.0.0 | Hide Composer hook |
| v1.0.0 | Download Story (init) |
| v1.0.0 | Download Video (long press) |
| v1.0.0 | Reels button (long press) |
| v1.0.0 | Lazy install Reels hook |
| v1.0.0 | Button with delay + screen bounds fallback |
| v1.0.0 | **CRITICAL FIX**: cast self as UIViewController to get .view |
| v1.0.0 | Switch to viewWillAppear: hook |
| v1.0.0 | Hook ALL Reels classes |
| v1.0.0 | Reels button: zPosition + keyWindow fallback |
| v1.0.0 | Add viewWillDisappear: hook for cleanup |
| v1.0.0 | Button in FBVideoHomePassthroughView (right column) |
| **v1.2.16** | **Hook FBShortsSideBarView.layoutSubviews (perfect alignment)** |
| **v1.2.17** | **isInReelsContext() filter (prevents button in comment sheet)** |

## Hooks (current count: 11)

1. FBMemNewsFeedEdge.node → nil for SPONSORED
2. FBComponentCollectionViewDataSource cellForItem
3. FBComponentCollectionViewDataSource willDisplay
4. FBSnacksBucketsSeenStateManager markThreadsViewReceiptsAndLightweightReactionsAsSeen
5. FBSnacksBucketsSeenStateManager _markThreadAsSeen
6. FBSnacksBucketsSeenStateManager _sendSeenThreadIDsWithBucket
7. UIViewController.viewDidAppear (settings + lazy install)
8. FBNewsFeedViewController.viewDidLoad (composer hide)
9. FBSnacksMediaContainerView (init + didMoveToWindow) → long press for story
10. FBVideoOverlayPluginComponentBackgroundView.didLongPress → video download
11. **FBShortsSideBarView.layoutSubviews → Reels download button**

## File Layout

- `Tweak.x`: 1985 lines, all hooks
- `control`: v1.2.17
- `Makefile`: GlowV3
- `GlowV3.plist`: filter for `com.facebook.Facebook` + `com.facebook.Facebook6`

## Key Settings

| Key | Default | Description |
|-----|---------|-------------|
| `s_removeAds` | YES | Block ads in home feed |
| `s_disableStorySeen` | YES | Don't mark stories as seen |
| `s_downloadVideo` | NO | In-feed video long-press download |
| `s_downloadStory` | NO | Story long-press download |
| `s_removePYMK` | NO | (not yet implemented) |
| `s_hideComposer` | YES | Hide composer in newsfeed |
| `s_hideOverlay` | NO | (not yet implemented) |
| `s_downloadReels` | YES | Reels button (v1.2.17) |

## Build Commands

```bash
cd /tmp/facebook-no-ads
rm -rf .theos/ packages/
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i /home/tommy/test/glow/facebook.ipa -o /tmp/glow_v8.ipa \
    -f packages/com.tommy.glowv3_1.2.17_iphoneos-arm.deb \
    --overwrite -s -d
cp /tmp/glow_v8.ipa /home/tommy/test/glow/glow_v8.ipa
```

## Sideload

1. Open TrollStore
2. Long press Facebook icon → Remove → Delete
3. Install `glow_v8.ipa`
4. Open Facebook → wait 3s for hooks to install
5. Verify: no ads, story seen, settings (long press Reel), Reels download button

## Git

- Branch: `v8-glow-framework`
- Repo: `https://github.com/Long-Trinh-Tien/facebook-no-ads.git`

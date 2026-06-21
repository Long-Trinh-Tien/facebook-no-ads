# v8 — Framework Port from Original Glow

> Status: **PLANNING** — Framework structure being built
> Branch: `v8-glow-framework` (next)
> Base: `analysis/glow-original` + glow_v7 working hooks

## Goal

Build a tweak that:
1. ✅ Keeps the **working 560.x hooks** from `glow_v7` (ad blocking + story seen)
2. 🆕 Clones the **framework architecture** from original Glow 1.3.1:
   - Multi-group `%ctor` with `%init(group)` pattern
   - Settings storage (`GlowUserDefaults`)
   - Localization (11 languages)
   - Settings view controller (UI)
   - Long-press menu
   - Multi-feature toggleable
3. 🆕 Ports Glow's **features** that fit 560.x:
   - Download video (long press)
   - Download story (button)
   - Hide "People You May Know"
   - Hide "Suggested for you"
   - Hide Reels carousel
   - Disable auto-advance reels
   - Composer hide
   - Disable automatic next story
   - Confirmation on like

## Architecture (from Glow 1.3.1 binary analysis)

Glow uses these own classes (extracted from `__objc_classlist`):

```
WelcomeVC                    // Onboarding screen
SettingsViewController       // Settings UI
ChangelogVC                  // Changelog
GlowUserDefaults             // Settings storage
ToastView / ToastManager     // Notifications
Downloader / DownloaderHelper// Download manager
FFMpegHelper / FFmpegKit     // Media conversion
DVNLongPressGestureRecognizer// Long press detector
DVNSheetController           // Sheet UI
```

We don't need FFmpeg (just save raw media). We do need:
- Settings storage ✓ simple
- Settings UI ✓ can be simple toggle list
- Downloader ✓ NSURLSession + save to Photos
- Long press ✓ UIGestureRecognizer

## Build Plan

### Stage v8.0 — Framework
- [x] Analyze original Glow 1.3.1 (`analysis/glow-original/`)
- [x] Document comparison
- [ ] Create v8 framework: settings storage + multi-group init pattern
- [ ] Localize (copy vi translation as starter)
- [ ] Build + test v8.0 framework runs without crash

### Stage v8.1 — Working hooks (port from v7)
- [ ] Ad blocking: `FBMemNewsFeedEdge.node` returning nil
- [ ] Story seen: 3 paths blocked
- [ ] Verify working on device

### Stage v8.2 — Download video (long press)
- [ ] Discover correct class for video container in 560.x
- [ ] Add long-press gesture
- [ ] Save HD/SD via NSURLSession
- [ ] Save to Photos

### Stage v8.3 — Download story (button)
- [ ] Discover correct init selector for `FBSnacksMediaContainerView` in 560.x
- [ ] Add download button
- [ ] Wire to downloader
- [ ] Save to Photos

### Stage v8.4 — Hide sections
- [ ] Hide Reels carousel
- [ ] Hide PYMK
- [ ] Hide Suggested
- [ ] Hide Composer

### Stage v8.5 — Reels features
- [ ] Disable auto-advance
- [ ] Like confirmation
- [ ] Reels like confirm

### Stage v8.6 — Settings UI
- [ ] SettingsViewController with toggles
- [ ] Open via long press on tab bar
- [ ] 11 languages

## What's Working Today (glow_v7)

| Feature | Hook | Status |
|---------|------|--------|
| Ad blocking | `FBMemNewsFeedEdge.node` → nil for SPONSORED | ✅ WORKS |
| Story seen | 3 paths on `FBSnacksBucketsSeenStateManager` | ✅ WORKS |
| Bundle filter | both `Facebook` + `Facebook6` | ✅ |
| Logging | `/var/mobile/Documents/glow.txt` | ✅ |

## What Glow Has But v7 Doesn't

| Feature | Glow 1.3.1 | v7 | Needed for v8? |
|---------|-----------|----|----|
| Download video | long press | ❌ | YES - core Glow feature |
| Download story | button | ❌ | YES - core Glow feature |
| Hide PYMK | section hide | ❌ | YES - core Glow feature |
| Hide Suggested | section hide | ❌ | YES - core Glow feature |
| Hide Reels carousel | section hide | ❌ | YES |
| Hide composer | `shouldHideComposer` hook | ❌ | YES |
| Disable auto-advance | `_advanceToNextItemWithNavigationAction:` | ❌ | YES |
| Like confirm | `setSelected:`/gesture check | ❌ | YES |
| Mark as seen button | long press menu | ❌ | YES |
| Settings UI | `SettingsViewController` | ❌ | YES |
| Onboarding | `WelcomeVC` | ❌ | NO (optional) |
| Update checker | `Update.Tweak` | ❌ | NO |
| Discord / social | `Discord.Desc` | ❌ | NO |
| FFmpeg re-encoding | `FFmpegHelper` | ❌ | NO (unnecessary) |
| Clear cache | `ClearCache` | ❌ | YES (simple) |
| Auto clear cache on launch | `AutoClearCache` | ❌ | YES |
| Notify updates | `NotifyUpdates` | ❌ | NO |
| Encoding speed (3 levels) | `EncodingSpeed` | ❌ | NO (no encoding) |

## Runtime Verification Needed

These need on-device testing with our runtime verifier (R3.0-verify):

1. What's the current init selector for `FBSnacksMediaContainerView` in 560.x?
2. Does `FBVideoOverlayPluginComponentBackgroundView` still exist in 560.x?
3. What methods does it have?
4. What's the class for Reels carousel (and how to hide it)?
5. What's the class for "People You May Know" section?
6. What's the class for "Suggested for you" section?
7. Does `FBNewsFeedViewControllerConfiguration` still exist?
8. What's the class for the Reels video player that auto-advances?

## Build Command

```bash
cd /home/tommy/test/facebook-no-ads
git checkout -b v8-glow-framework
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i /home/tommy/test/glow/facebook.ipa -o glow_v8.ipa -f com.tommy.glowv3_1.0.0_iphoneos-arm.deb --overwrite -s -d
```

## Risks

1. **FBVideoOverlayPluginComponentBackgroundView** — exists in 560.x per R3.0-verify, signature change possible
2. **FBSnacksMediaContainerView** — NEW init signature per R3.0-verify, need to discover it
3. **Settings UI** — can be a simple alert with toggles, doesn't need full VC
4. **Localization** — copying strings files is straightforward
5. **FFmpeg re-encoding** — skip, just save raw

## Success Criteria for v8

- [ ] Builds without errors
- [ ] Installs without crash
- [ ] Ad blocking still works
- [ ] Story seen still blocked
- [ ] At least 2 new features work (download story + hide PYMK)
- [ ] Settings toggles affect behavior
- [ ] App doesn't crash on enable/disable toggles

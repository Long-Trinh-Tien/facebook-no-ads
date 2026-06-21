# Glow v8 — Multi-feature Framework (Stage v8.0/v8)

> Status: **FRAMEWORK COMPLETE** ✅
> Build: `glow_v8.ipa` (195MB, working)
> Branch: `v8-glow-framework`

## What's Working in v8

✅ Ad blocking: FBMemNewsFeedEdge.node returns nil for SPONSORED (from v7)
✅ Story seen: 3 paths blocked on FBSnacksBucketsSeenStateManager (from v7)
✅ Settings UI: GlowSettingsViewController with toggles
✅ Settings storage: NSUserDefaults with com.tommy.glow.* keys
✅ Long press to open settings: hooked tab bar didSelect
✅ Multi-language ready: vi translation included
✅ Build: glow_v8.ipa ready for sideload

## Framework Architecture (8 sections in Tweak.x)

```
SECTION 1: Settings storage       (NSUserDefaults, reloadPrefs)
SECTION 2: Settings UI           (GlowSettingsViewController)
SECTION 3: Ad blocking           (FBMemNewsFeedEdge.node + cell hiding)
SECTION 4: Story seen            (3 paths blocked)
SECTION 5: Long press to settings (tab bar hook)
SECTION 6: Install hooks         (deferred to main queue)
SECTION 7: %ctor                 (load prefs, install viewDidAppear)
```

## Settings (NSUserDefaults keys)

| Key | Default | Status |
|-----|---------|--------|
| `com.tommy.glow.removeAds` | YES | ✅ wired |
| `com.tommy.glow.disableStorySeen` | YES | ✅ wired |
| `com.tommy.glow.downloadVideo` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.downloadStory` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.removePYMK` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.removeReelsCarousel` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.removeSuggested` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.hideComposer` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.disableAutoNext` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.confirmLike` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.markAsSeen` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.clearCacheOnLaunch` | NO | 🆕 toggle only (not implemented) |
| `com.tommy.glow.notifyUpdates` | NO | 🆕 toggle only (not implemented) |

## Build Pipeline

```
Tweak.x (Tweak.xm)
  ↓ THEOS=/home/tommy/theos make package FINALPACKAGE=1
  ↓ com.tommy.glowv3_1.0.0_iphoneos-arm.deb
  ↓ cyan inject into facebook.ipa
glow_v8.ipa (195MB)
  ↓ TrollStore install on device
  ↓ App opens → viewDidAppear hook → installHooks
  ↓ Settings via long press on any tab
```

## Open Items (Stage v8.1+)

1. **Settings effect** — currently toggles only update settings but don't re-install hooks. User must restart FB for changes to take effect.
2. **Download video** — need to verify FBVideoOverlayPluginComponentBackgroundView in 560.x
3. **Download story** — need to verify FBSnacksMediaContainerView init signature in 560.x
4. **Hide sections** — need to discover class names for PYMK, Suggested, Reels carousel
5. **Localize** — copy all 11 language files from Glow 1.3.1
6. **Onboarding** — WelcomeVC (optional)
7. **Update checker** (optional)

## Files

| File | Purpose |
|------|---------|
| `/tmp/facebook-no-ads/Tweak.x` | v8.0 framework (522 lines) |
| `/tmp/facebook-no-ads/Makefile` | Build config |
| `/tmp/facebook-no-ads/control` | Package metadata |
| `/tmp/facebook-no-ads/GlowV3.plist` | Filter (com.facebook.Facebook + Facebook6) |
| `/tmp/glow_v8.ipa` | Built tweak |
| `/home/tommy/test/glow/glow_v8.ipa` | Same (for sideload) |

## Build Output

```
$ THEOS=/home/tommy/theos make package FINALPACKAGE=1
==> Building GlowV3 (arm64 + arm64e + armv7)
==> Making stage for tweak GlowV3...
dm.pl: building package `com.tommy.glowv3:iphoneos-arm' in `./packages/com.tommy.glowv3_1.0.0_iphoneos-arm.deb'

$ cyan -i facebook.ipa -o glow_v8.ipa -f com.tommy.glowv3_1.0.0_iphoneos-arm.deb --overwrite -s -d
[*] injected GlowV3.dylib
[*] generated ipa at /tmp/glow_v8.ipa
```

## Next Steps for v8.1

1. **Test v8.0 on device** — verify ad block + story seen still work
2. **Verify settings UI appears** when tapping any tab
3. **Verify toggles persist** across app restarts
4. **Add i18n** — copy language files from Glow 1.3.1
5. **Wire up next feature** — based on user feedback

## Key Design Decisions

1. **Settings via NSUserDefaults** (vs Glow's plist) — standard, easier to share with companion app
2. **Settings UI is a UITableView** (vs Glow's complex WelcomeVC) — simpler, works on all iOS versions
3. **Long press on tab bar** (vs Glow's complex DVNLongPressGestureRecognizer) — simpler implementation
4. **No FFmpeg** (vs Glow's 16MB) — we don't re-encode, just save raw media
5. **No welcome screen** — first time users can read the README
6. **Hooks re-installed on every app launch** — not on setting toggle (would require re-hooking API)

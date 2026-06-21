# R4 Verifier

**Status:** v1.6.0 (targeted, no global enumeration)

Tweak to dump methods/ivars/properties of FB classes for v8.2+ feature
discovery. Does **NOT** install any actual hooks — read-only introspection.

## What's in v1.6.0

- **Phase 1**: ~16 critical classes with full method/ivar/property dump
- **Phase 2-7**: Candidate class lookup (just FOUND/NOT FOUND, no full dump)
  - Phase 2: 30 Reels candidates
  - Phase 3: 17 Video container candidates
  - Phase 4: 14 Story viewer candidates
  - Phase 5: 33 UI Hide candidates
  - Phase 6: 12 Download/share candidates
  - Phase 7: 37 Reels action button candidates
- **Phase 9**: UIViewController.viewDidAppear: hook + subview walk
- **Phase 10**: UIView.layoutSubviews hook (for late subview adds)
- **Phase 11**: UIView.didAddSubview: hook (catch any subview addition)
- **Timed walks**: +0/+1/+3/+5/+10s after VC appears

## Outputs

### File output
`/var/mobile/Documents/glow_r4.txt` (append mode)

### Console output
Open Console.app → filter `GlowR4`

## Key Findings (FB 560.x)

### Reels structure (verified v1.6.0)
```
FBShortsViewerOverlayComponentView (full screen overlay)
└── FBPassthroughView (content area, 12,12,416,333)
    ├── FBPassthroughView (author/follow, 0,218,360,97)
    ├── FBPassthroughView (description, 0,86,372,0)
    ├── FBShortsDescriptionView (text)
    └── FBShortsSideBarView (360,0,56,333) ← RIGHT ACTION COLUMN
        ├── FDSTouchStateAnnouncingControl Like (0,0,56,72)
        ├── FDSTouchStateAnnouncingControl Comment (0,72,56,72)
        ├── FDSTouchStateAnnouncingControl Share (0,145,56,72)
        ├── FDSTouchStateAnnouncingControl Save (0,217,56,72)
        └── FDSTouchStateAnnouncingControl More (0,289,56,44)
```

### Reels VCs (4 of them)
- `NSKVONotifying_FBVideoHomeViewController` (root)
- `FBVideoHomeUnifiedPlayerViewController` (player)
- `FBVideoHomeFeedSurfaceViewController` (feed surface)
- `FBSurfaceViewControllerImpl` (impl)

### Comment sheet (for context — DON'T add Reels button here!)
- `FBBottomSheetViewController`
- `FBCommentStreamViewController`
- `FBPSUnifiedShareSheetViewController`

### IMPORTANT: FBShortsSideBarView is also in comment sheets!
This is why v8.2.17 added `isInReelsContext()` filter. If you see button
appearing in comments, the filter is broken.

## How to build

```bash
cd /tmp/facebook-no-ads/analysis/r4-verifier
rm -rf .theos/ packages/
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i /home/tommy/test/glow/facebook.ipa -o /tmp/glow_r4.ipa \
    -f packages/com.tommy.glowr4_1.6.0_iphoneos-arm.deb \
    --overwrite -s -d
cp /tmp/glow_r4.ipa /home/tommy/test/glow/glow_r4.ipa
```

## How to use

1. Remove Facebook app
2. Install `glow_r4.ipa` (separate bundle ID `com.tommy.glowr4`)
3. Open app, wait 3s
4. Navigate to feature you want to discover
5. Get `/var/mobile/Documents/glow_r4.txt`
6. Or check Console.app → filter `GlowR4`

## Crash history

- v1.0/v1.1 (R1): `objc_copyClassList` with 10000+ classes → crash
- v1.0/v1.1 (R2): aggressive chain walk into FBNewsFeedViewController → crash
- v1.2: removed `objc_copyClassList` enumeration, used targeted candidates
- v1.3: removed Phase 8 enum, added subview walk
- v1.4: added NSLog (3 layers), fflush per call, multi-path file
- v1.5: 5-level walk + layout hook
- v1.6: 7-level walk + timed walks + didAddSubview hook

## Branch info

- Source: `r4-verifier` branch (original)
- Latest: branch `v8-glow-framework` keeps a copy in `analysis/r4-verifier/`
- See COMPACT_SESSION.md in project root for full context

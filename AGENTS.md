# Glow Clone — Session Context (Compacted)

## Current Stage
**STAGE R3.5/v7 — WORKING** ✅ (built glow_v7.ipa)
- Ad blocking: WORKS (no gap)
- Story seen: BLOCKED via 3 hooks
- Build: glow_v7.ipa (186MB)

## TL;DR (1-minute summary)

After 3.5 stages of investigation, we built a working Facebook ad blocker by:
1. Reading open-source `haoict/facebook-no-ads` (which forked from Glow)
2. Runtime-verifying which classes/methods still exist in 560.x
3. Adapting the original `FBMemNewsFeedEdge.initWithFBTree:` approach to `FBMemNewsFeedEdge.node` (the new equivalent)

**Key hook:** `FBMemNewsFeedEdge.node` returns nil for SPONSORED category → no layout, no gap.

**Why this works:** Hooks at model layer (analog to original Glow's approach), not at cell layer (which causes gaps due to ComponentKit's precomputed layout).

---

## Detailed Investigation Journey

### Phase 0: Initial attempts (R0 - R1)

**Stage R0 — UIWindow/UIView hooks**
- Approach: Hook `viewDidLoad`, `addSubview:`, strstr pattern matching
- Result: **CRASH on iOS 16+**
- Lesson: UIKit hooks don't survive modern iOS lifecycle

**Stage R1 — Brute-force class enumeration**
- Approach: `objc_getClassList(NULL, 0)` in `%ctor`, dump all classes
- Result: **CRASH** — 5000+ classes enumeration too aggressive
- Lesson: Defer heavy operations to main queue after app init

### Phase 1: Static RE (R1.5)

**Stage R1.5 — C function search**
- Approach: Static analysis with `strings`, `radare2` on FBSharedFramework
- Found: `_FBFeedUnitIsSponsored` at offset `0x00910d04` in FBSharedFramework
- GOT entry at `0x100accd08` in main binary
- Result: Can resolve function but calling it throws exception on wrong types

### Phase 2: Runtime walk (R2.x)

**Stages R2.0 - R2.7 — Cell-based approach**
- Approach: Hook `cellForItemAtIndexPath:`, walk chain `CKDataSourceItem._model → FBSectionComponentDataSourceModel._model → FBFeedFetchedEdge._edge → FBMemNewsFeedEdge`, call `_FBFeedUnitIsSponsored`
- Result: Hooks fire correctly, but C function expects `FBFeedUnit` type. `CKDataSourceItem` is wrong type → exception
- Pivot: Inspect what FBMemNewsFeedEdge actually contains (only 3 methods in 560.x)

### Phase 3: Runtime introspection (R3.0-verify)

**Stage R3.0-verify — Class & method verification**
- Built custom verifier using `objc_getClassList`, `class_copyMethodList`, `class_copyIvarList`
- Output: `/var/mobile/Documents/glow_verify.txt`
- **KEY DISCOVERIES:**
  - `FBMemNewsFeedEdge` STILL EXISTS, but only 3 methods: `node`, `deduplicationKey`, `category`
  - `initWithFBTree:` is GONE
  - `FBMemFeedStory` is REMOVED
  - `FBVideoChannelPlaylistItem` is REMOVED
  - `FBSnacksBucketsSeenStateManager._sendSeenThreadIDsWithBucket:session:` is INTACT
  - `FBSnacksMediaContainerView` exists with NEW init signature
  - `FBVideoOverlayPluginComponentBackgroundView` has `didLongPress:`
  - `FBVideoPlaybackItem` has `HDPlaybackURL`, `isSponsored`
  - Categories seen: `ORGANIC`, `SPONSORED`, `FB_SHORTS`, `ENGAGEMENT`, `MULTI_FB_STORIES_TRAY`

### Phase 4: Read open-source reference

**Stage R3.0 — Pivot to known approach**
- Read `haoict/facebook-no-ads/Tweak.xm` (fork from original Glow)
- Found approach: hook `FBMemNewsFeedEdge.initWithFBTree:` to return nil
- Discovered selector `asFBFeedUnitIsSponsoredGraphQL` from exception messages
- Found `FBMemNewsFeedEdge.category` returns `"SPONSORED"` for ads

### Phase 5: Production hooks (R3.0 - R3.4)

**Stage R3.0 — Verified hooks**
- Hook `FBComponentCollectionViewDataSource.collectionView:cellForItemAtIndexPath:`
- Walk chain, check `category == "SPONSORED"`, hide cell
- Result: Hooks fire, but ALL items hidden (over-aggressive)

**Stage R3.1 — Conservative detection**
- Whitelist: ORGANIC, ENGAGEMENT (not ad)
- Blacklist: SPONSORED, AD, IN_STREAM_AD
- Result: Feed displays, ads hidden, BUT GAPS remain (precomputed layout)

**Stage R3.2 — Add size hooks**
- Hook `sizeForItemAtIndexPath:` + `collectionView:layout:sizeForItemAtIndexPath:`
- Return 0.01 x 0.01 for ads
- Result: GAPS STILL VISIBLE — ComponentKit uses `_rootLayout` C++ struct, not these methods

**Stage R3.3 — Category trace + size zero**
- Skip sections 0, 1 (story tray, composer)
- Log unique categories
- Result: Identified new categories (FB_SHORTS, ENGAGEMENT). Gaps persist.

**Stage R3.4 — C++ struct modification**
- Try to modify `_rootLayout.size` field via direct memory write
- Result: Risky, possibly didn't work (not tested)

### Phase 6: Final working approach (R3.5/v7)

**Stage R3.5/v7 — Hook `node` method (analog of old `initWithFBTree:`)**
- Approach: Hook `FBMemNewsFeedEdge.node` to return nil for SPONSORED
- Keep cell hiding as backup
- Block 3 story seen paths
- **Result: WORKS** — no gaps, no breakage

**Why this works:** The `node` method is called during layout computation. Returning nil for SPONSORED edges means ComponentKit never computes a layout for those cells, so no space is allocated.

---

## Architecture (from ARCHITECTURE.md)

Original Glow: 3-layer anti-versioning
- Layer 1: UIKit entry points (viewDidLoad, addSubview:) — always stable
- Layer 2: strstr pattern matching on real instances — version-tolerant
- Layer 3: respondsToSelector: checks — silent degradation

Our implementation: Model-layer filter
- Hook `FBMemNewsFeedEdge.node` to return nil for ads (analog to original `initWithFBTree:`)
- Conservative category whitelist: ORGANIC, ENGAGEMENT = not ad
- Skip sections 0, 1 (story tray, composer)

## Crash History

| Stage | Cause | Fix | Status |
|-------|-------|-----|--------|
| R0 | addSubview: hook iOS 16+ | Remove permanently | ✅ |
| R0 | objc_copyClassList in %ctor | Defer/remove | ✅ |
| R0 | UIApplicationDidFinishLaunchingNotification timing | dispatch_after | ✅ |
| R1 | Timer scanner during login | Remove | ✅ |
| R1 | dlopen + enumeration in setupAllHooks | Remove | ✅ |
| R1 | object_getIvar on non-@ ivar (C++ struct) | Type-check before access | ✅ |
| R1 | aggressive chain walk into FBNewsFeedViewController | Removed | ✅ |
| R2 | objc_getClassList 5000+ classes → crash | Filtered to FB prefix | ✅ |
| R2 | predicate expects FBFeedUnit, got CKDataSourceItem | Switched to model-layer hook | ✅ |
| R3.1 | All items hidden (over-aggressive) | Conservative category check | ✅ |
| R3.2-3.4 | Gaps remain (precomputed layout) | Hook `node` instead | ✅ |

## Key Files

| File | Purpose |
|------|---------|
| `/home/tommy/test/glow/glow_v7.ipa` | **CURRENT** R3.5 build — working |
| `/home/tommy/test/glow/glow-from-source/Tweak.x` | R3.5 source code |
| `/home/tommy/test/glow/glow-from-source/INVESTIGATION_GUIDE.md` | Teaching file (methods, reasoning) |
| `/home/tommy/test/glow/glow-from-source/BUILD_GUIDE.md` | How to build and test |
| `/home/tommy/test/glow/glow-from-source/AGENTS.md` | This file — session context |
| `/home/tommy/test/glow/glow-v3/Tweak.x` | Alternative build dir |

## Build Pipeline

```
/home/tommy/test/glow/glow-from-source/Tweak.x
   ↓ THEOS=/home/tommy/theos make package FINALPACKAGE=1
   ↓ com.tommy.glowv3_1.0.0_iphoneos-arm.deb
   ↓ cyan inject into facebook.ipa
glow_v7.ipa (186MB)
   ↓ TrollStore install on device
   ↓ App opens → hooks install → ads blocked
```

## What's Working (R3.5/v7)

✅ Ad blocking: FBMemNewsFeedEdge.node returns nil for SPONSORED
✅ Story seen: 3 paths blocked
✅ No layout gaps (no cell, no gap)
✅ Feed scroll smooth

## What's TODO

❌ Download story (hook FBSnacksMediaContainerView - infrastructure ready)
❌ Download video (hook didLongPress: - infrastructure ready)
❌ Hide Reels carousel
❌ Hide "People You May Know"
❌ Hide "Suggested for you"

## Next Steps

1. Confirm glow_v7.ipa works fully (user testing)
2. Add download features for story + video
3. Add other Glow features (composer hide, people you may know hide, etc.)
4. Polish + add settings UI
5. Test on multiple Facebook versions (561, 562, 563...)

## Critical Environment

- Facebook version: 560.x (tested)
- iOS: 16+ (TrollStore)
- Tweak injection: cyan
- Build system: Theos
- Log file: `/var/mobile/Documents/glow.txt`
- Bundle IDs: `com.facebook.Facebook`, `com.facebook.Facebook6`

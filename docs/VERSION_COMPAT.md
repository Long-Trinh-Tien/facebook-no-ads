# Facebook Version Compatibility Matrix

> Track API changes qua các versions FB để biết tweak có cần update không.

## Current Status

| FB Version | Date | Status | Notes |
|------------|------|--------|-------|
| **560.x** | 2025-06-20 | ✅ **Working** | R3.5/v7 — `node` hook, 3 seen hooks |
| 555.0.0 | - | ⚠️ Untested | Should work (API stable) |
| 561+ | - | ❓ Unknown | Need to verify |

## API Matrix

| API | 555.x | 560.x | 561.x | 562.x |
|-----|-------|-------|-------|-------|
| `FBMemNewsFeedEdge` class | ✓ | ✓ (3 methods) | ? | ? |
| `node` method | ✓ | ✓ | ? | ? |
| `category` method | ✓ | ✓ | ? | ? |
| `_sendSeenThreadIDsWithBucket:session:` | ✓ | ✓ | ? | ? |
| `_sendThreadIDsAsSeenInViewerSession:` | ✓ | ✓ | ? | ? |
| `markThreadsViewReceipts...` | ✓ | ✓ | ? | ? |
| `FBSnacksMediaContainerView` | ✓ | ✓ (new init sig) | ? | ? |
| `FBVideoOverlayPluginComponentBackgroundView` | ✓ | ✓ (has didLongPress:) | ? | ? |
| `FBVideoPlaybackItem.HDPlaybackURL` | ✓ | ✓ | ? | ? |
| `FBComponentCollectionViewDataSource` | ✓ | ✓ | ? | ? |
| `FBNewsFeedCollectionView` | ✓ | ✓ | ? | ? |

## Categories Matrix

| Category | 555.x | 560.x | 561.x | 562.x |
|----------|-------|-------|-------|-------|
| ORGANIC | ✓ | ✓ | ? | ? |
| SPONSORED | ✓ | ✓ | ? | ? |
| AD | ✓ | ✓ | ? | ? |
| IN_STREAM_AD | ✓ | ✓ | ? | ? |
| ENGAGEMENT | ✓ | ✓ | ? | ? |
| FB_SHORTS | ✓ | ✓ | ? | ? |
| MULTI_FB_STORIES_TRAY | ✓ | ✓ | ? | ? |

## Update Procedure

See [UPDATE_GUIDE.md](UPDATE_GUIDE.md) for full workflow.

Quick version:
1. Build verifier
2. Install, get log
3. Compare with last known good
4. Update Tweak.x
5. Rebuild, test

## Historical Changes

### 560.x (Current — Working)
- **FBMemFeedStory** REMOVED
- **FBVideoChannelPlaylistItem** REMOVED
- **FBMemNewsFeedEdge** reduced to 3 methods (was more)
- **initWithFBTree:** REMOVED from FBMemModelObject (replaced with `initWithFBPandoTree:`)
- **FBSnacksMediaContainerView** init signature changed: added `shouldBlurMedia:` param
- **VideoContainerView** `syc:`/`nyc:` selectors REMOVED
- **Tweak.x adaptation:** Hook `node` method instead of `initWithFBTree:`

### Earlier (550-555.x)
- Original Glow: hook `FBMemNewsFeedEdge.initWithFBTree:` to return nil
- Also hook `FBMemFeedStory.initWithFBTree:` to return nil
- Also hook `FBVideoChannelPlaylistItem.Bi:...:`
- Story seen: hook `FBSnacksBucketsSeenStateManager._sendSeenThreadIDsWithBucket:session:`

## Tested Devices

| Device | iOS | FB Version | Glow Version | Result |
|--------|-----|------------|--------------|--------|
| iPhone 12+ | 16+ | 560.x | v7 | ✅ Works |
| iPhone X | 14-15 | 555.0.0 | v1.0 | ⚠️ Untested |
| iPhone 11 | 16+ | 561.0.0 | ? | ❓ Unknown |

## Test Checklist

When testing on new version:

- [ ] Open Facebook, see news feed
- [ ] Verify organic posts display
- [ ] Verify ads are hidden (no gaps)
- [ ] Open story, view it
- [ ] Check story tray of friend — should NOT show "seen"
- [ ] Scroll smoothly (no jumps, no missing posts)
- [ ] No crashes during normal use
- [ ] Check `/var/mobile/Documents/glow.txt` for errors

## Build Outputs

| File | Purpose | Status |
|------|---------|--------|
| `glow_v7.ipa` | R3.5/v7 production | ✅ Latest |
| `glow_verify.ipa` | Verifier for new versions | ✅ Always keep |
| `glow_flex.ipa` | FLEX explorer (limited) | ⚠️ Optional |

## Future Versions

When new FB version ships:
1. Add row to API Matrix above (mark as "Unknown")
2. Run verifier on new binary
3. Update matrix with findings
4. If changes needed, follow UPDATE_GUIDE.md
5. Update this file with new "Historical Changes" entry
6. Commit + push

## References

- [BUILD_GUIDE.md](BUILD_GUIDE.md) — How to build
- [UPDATE_GUIDE.md](UPDATE_GUIDE.md) — How to update
- [INVESTIGATION_GUIDE.md](INVESTIGATION_GUIDE.md) — Full investigation journey
- [AGENTS.md](AGENTS.md) — Session context

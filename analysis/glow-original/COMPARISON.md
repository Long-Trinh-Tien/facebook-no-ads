# Glow Original vs Glow v8.2.17 — Comparison

> **Date**: 2026-06-21 17:05 UTC
> **Original**: Glow 1.3.1 (closed source, decompiled via haoict fork)
> **v8.2.17**: Our rebuild for FB 560.x

---

## Summary

| Feature | Original Glow 1.3.1 | v8.2.17 |
|---------|---------------------|---------|
| Ad block (home feed) | ✅ | ✅ |
| Story seen | ✅ | ✅ (3 paths) |
| Download story | ✅ | ✅ (long press) |
| Download video (in-feed) | ✅ | ✅ (long press) |
| Reels download | ✅ | ✅ (button) |
| Hide composer | ✅ | ✅ |
| PYMK hide | ✅ | ❌ (TODO) |
| Suggested hide | ✅ | ❌ (TODO) |
| Localize to 11 langs | ✅ | ⚠️ (vi only) |

---

## Critical Class Names (CONFIRMED via runtime R4 v1.6)

### 1. Ad block — `FBMemNewsFeedEdge.node`
| Property | Original (Glow 1.3.1) | v8.2.17 |
|----------|---------------------|---------|
| Method | `node` returns nil if SPONSORED | Same ✅ |
| Categories | ORGANIC, ENGAGEMENT kept | Same ✅ |
| Blocked | SPONSORED, AD, IN_STREAM_AD | + PROMOTION (v8.2.4+) |

### 2. Story seen — `FBSnacksBucketsSeenStateManager`
| Path | Original | v8.2.17 |
|------|----------|---------|
| `markThreadsViewReceiptsAndLightweightReactionsAsSeen:bucket:session:isHighlight:successBlock:noThreadsToMarkAsSeenBlock:` | ✅ noop | ✅ noop |
| `_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:skipSeenMutationForLastUnseenThread:` | ✅ noop | ✅ noop |
| `_sendSeenThreadIDsWithBucket:session:` | ✅ noop | ✅ noop |

### 3. Download story — `FBSnacksMediaContainerView`
| Aspect | Original | v8.2.17 |
|--------|----------|---------|
| Init signature | 5 args | **6 args + BOOL** (FB 560 changed!) |
| Hook point | didMoveToWindow + UILongPress | Same ✅ |
| Video source | `manager.currentVideoPlaybackItem.HDPlaybackURL` | Same ✅ |
| Photo source | `webPhotoView.photo.allInfoURLs` | **Same** but `imageSpecifier` access fails |

### 4. Download video (in-feed) — `FBVideoOverlayPluginComponentBackgroundView`
| Aspect | Original | v8.2.17 |
|--------|----------|---------|
| Hook | `didLongPress:` | Same ✅ |
| Long press | UILongPressGestureRecognizer | Same ✅ |
| Video URL | `playbackController.currentItem.HDPlaybackURL` | Same ✅ |

### 5. Reels download — **MAJOR DIFFERENCE**
| Aspect | Original (1.3.1) | v8.2.17 |
|--------|------------------|---------|
| Approach | Hook `FBMemNewsFeedEdge.initWithFBTree:` → return nil | Hook `FBShortsSideBarView.layoutSubviews` |
| Why | Old FB: hide Reels in feed | New FB: button next to like/share |
| Layout gap | Yes (no layout) | **No gap** (button in sidebar) |
| Position | Top of Reel (overlay) | Right column (with like/share) |
| Filter needed | No | **YES** (v8.2.17) — `isInReelsContext()` |

### 6. Reels structure (FB 560.x — verified by R4 v1.6)
```
FBShortsViewerOverlayComponentView (full screen overlay)
└── FBPassthroughView (content area)
    ├── FBPassthroughView (author/follow)
    ├── FBPassthroughView (description)
    ├── FBShortsDescriptionView (text)
    └── FBShortsSideBarView (360,0,56,333) ← RIGHT ACTION COLUMN
        ├── FDSTouchStateAnnouncingControl Like (0,0,56,72)
        ├── FDSTouchStateAnnouncingControl Comment (0,72,56,72)
        ├── FDSTouchStateAnnouncingControl Share (0,145,56,72)
        ├── FDSTouchStateAnnouncingControl Save (0,217,56,72)
        └── FDSTouchStateAnnouncingControl More (0,289,56,44)
```

---

## Class Names That DON'T Exist in 560.x (renamed/removed)

| Original class | Status in 560.x |
|---------------|-----------------|
| `FBMemFeedStory` | REMOVED (Glow 1.3.1 used this) |
| `FBVideoChannelPlaylistItem` | REMOVED |
| `FBMemSuggestedForYouEdge` | REMOVED (class no longer exists) |
| `FBMemSuggestedEdge` | REMOVED |
| `FBMemPeopleYouMayKnowEdge` | **EXISTS** but 0 methods (no working hook) |
| `FBMemPYMK*` | REMOVED |
| `FBMemShorts*` | REMOVED |
| `FBReels*`, `FBReel*` | **REMOVED** (renamed to `FBShorts*`) |
| `FBSnacksStoryViewer*` | REMOVED (renamed/restructured) |
| `FBComposerViewController` | EXISTS (R4 Phase 5 found 1/33) |

## Class Names That EXIST in 560.x (verified)

| Class | Methods | Purpose |
|-------|---------|---------|
| `FBMemNewsFeedEdge` | 59 | Feed edge, has `node`, `category` |
| `FBSnacksBucketsSeenStateManager` | 6 | Story seen (3 paths) |
| `FBComponentCollectionViewDataSource` | 86 | Newsfeed data source |
| `FBNewsFeedViewController` | 180 | Newsfeed VC |
| `FBNewsFeedViewControllerConfiguration` | 7 | Has `_shouldHideComposer` |
| `FBSnacksMediaContainerView` | 17 | Story media container |
| `FBSnacksNewVideoView` | 39 | Story video |
| `FBSnacksPhotoView` | 68 | Story photo |
| `FBSnacksWebPhotoView` | 24 | Web photo |
| `FBWebPhotoView` | 37 | Image viewer |
| `FBWebImageNetworkSpecifier` | 15 | Image network |
| `FBWebImageMemorySpecifier` | 9 | Image memory |
| `FBVideoPlaybackItem` | 81 | Video playback |
| `FBVideoOverlayPluginComponentBackgroundView` | 8 | In-feed video overlay |
| `FBVideoHomeViewController` | unknown | Reels root |
| `FBVideoHomeUnifiedPlayerViewController` | unknown | Reels player |
| **`FBShortsSideBarView`** | unknown | **Reels right action column** |
| `FBShortsViewerOverlayComponentView` | unknown | Reels overlay |
| `FBShortsCustomHitTestView` | unknown | Custom hit test |
| `FBShortsDescriptionView` | unknown | Reels description |

---

## Settings Comparison

| Setting | Original | v8.2.17 |
|---------|----------|---------|
| Language | i18n (11 langs) | Vietnamese only (for now) |
| UI style | Modal sheet, X close, UPPERCASE sections, switches (not checkmarks) | Same ✅ |
| Toggle persistence | NSUserDefaults | Same ✅ |
| Onboarding | Yes (welcome screen) | No (TODO) |
| Update checker | Yes | No (TODO) |

---

## Technical Differences

| Aspect | Original | v8.2.17 |
|--------|----------|---------|
| Build system | Theos | Theos ✅ |
| iOS min | 13+ | 16+ (TrollStore only) |
| FB version | 350.x | 560.x |
| Binary protection | Hide symbols, encrypted strings | No (open source) |
| ObjC runtime | `objc_getClass` | `objc_getClass` ✅ |
| Memory | 10000+ class enum (slow) | **Avoided** (R4 uses targeted lists) |
| Logging | None visible | NSLog + file (R4 only) |

---

## Conclusion

**v8.2.17 has feature parity with original Glow 1.3.1 for core features**:
- ✅ Ad block
- ✅ Story seen
- ✅ Download story
- ✅ Download video (in-feed)
- ✅ Reels download
- ✅ Hide composer
- ❌ PYMK hide (TODO)
- ❌ Suggested hide (TODO)

**v8.2.17 BETTER than original** in some areas:
- Open source
- Better crash recovery
- More graceful FB update handling
- Detailed logging for debugging

**v8.2.17 WORSE** in:
- Language (vi only vs 11)
- No onboarding screen
- No update checker
- Less polished settings UI

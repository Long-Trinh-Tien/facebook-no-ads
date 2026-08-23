# 🎯 Quick Reference Card - FB 560.x Classes

**One-page reference for fast lookup during development**

---

## 📦 Core Classes

### Video
| Class | Address | Key Methods |
|-------|---------|-------------|
| `FBVideoPlaybackContainerView` | `0x06e4d3a8` | `initWithFrame:`, `layoutSubviews` |
| `FBVideoPlaybackController` | `0x06e4cfe8` | `currentVideoPlaybackItem` (0x0578dc7a) |
| `FBVideoPlaybackItem` | `0x06e7a3a8` | `HDPlaybackURL`, `SDPlaybackURL` |
| `FBShortsSideBarView` | (runtime) | `didMoveToWindow` |
| `FBShortsPlaybackController` | (runtime) | `playbackController` |

### Story
| Class | Address | Key Methods |
|-------|---------|-------------|
| `FBSnacksMediaContainerView` | (runtime) | `initWithThread:bucket:...` |
| `FBSnacksNewVideoView` | (runtime) | `manager` property |
| `FBSnacksMediaPlayerManager` | (runtime) | `currentVideoPlaybackItem` |
| `FBSnacksBucketsSeenStateManager` | (runtime) | `_sendSeenThreadIDsWithBucket:session:` |

### Feed
| Class | Address | Key Methods |
|-------|---------|-------------|
| `FBMemNewsFeedEdge` | (runtime) | `node` |
| `FBComponentCollectionViewDataSource` | (runtime) | `cellForItemAtIndexPath:`, `willDisplay` |

---

## 🔑 Key Properties

### FBVideoPlaybackController
```objc
@property (nonatomic, readwrite, strong) id controller;
@property (nonatomic, readwrite, strong) id videoPlaybackController;  // ⭐
@property (nonatomic, readonly, strong) id videoController;
@property (nonatomic, readwrite, strong) id videoPlayerController;
@property (nonatomic, readonly, strong) id warmedPlayer;
@property (nonatomic, readonly, strong) id playbackController;
```

### FBVideoPlaybackItem
```objc
@property (nonatomic, readonly, copy) NSURL *HDPlaybackURL;   // ⭐
@property (nonatomic, readonly, copy) NSURL *SDPlaybackURL;   // ⭐
@property (nonatomic, readonly, copy) NSURL *DashPlaybackURL;
@property (nonatomic, readonly, copy) NSURL *HLSPlaybackURL;
@property (nonatomic, readonly, copy) NSURL *sphericalPlaybackURL;
@property (nonatomic, readonly, copy) NSURL *videoURL;
@property (nonatomic, readonly, strong) id playbackItem;
@property (nonatomic, readonly, strong) id playbackItemMetadata;
@property (nonatomic, readonly, strong) id videoItem;
```

---

## ⚠️ CRITICAL: setPlaying: DOES NOT EXIST!

```objc
// ❌ WRONG - doesn't work
SEL sel = sel_registerName("setPlaying:");

// ✅ CORRECT alternatives
SEL sel1 = sel_registerName("setPlayingVideo:");     // BOOL param
SEL sel2 = sel_registerName("setPlayingRequested:"); // BOOL param
SEL sel3 = sel_registerName("currentVideoPlaybackItem"); // getter
```

---

## 🛠️ Quick Commands

```bash
# Find class address
rabin2 -s binary | grep "OBJC_CLASS_\$_ClassName"

# Get all properties
r2 -q -c "iz~ClassName" binary

# Find method selector
r2 -q -c "izz~methodName" binary

# Quick class scan
strings binary | grep "^FB" | sort -u
```

---

## 📐 Hook Patterns

### Pattern 1: Hook View Init
```objc
%hook FBVideoPlaybackContainerView
- (id)initWithFrame:(CGRect)frame {
    id result = %orig;
    // Add gesture, button, etc.
    return result;
}
%end
```

### Pattern 2: Get Controller from View
```objc
// Try property first
id controller = [view valueForKey:@"videoPlaybackController"];

// Try ivar
Ivar ivar = class_getInstanceVariable(cls, "_videoPlaybackController");
if (ivar) controller = object_getIvar(view, ivar);
```

### Pattern 3: Get Video Item
```objc
id controller = [view valueForKey:@"videoPlaybackController"];
id item = [controller currentVideoPlaybackItem];
NSURL *hdURL = [item HDPlaybackURL];
NSURL *sdURL = [item SDPlaybackURL];
```

### Pattern 4: Track Active Playback
```objc
// Hook setPlayingVideo: (CORRECT method)
%hook FBVideoPlaybackController
- (void)setPlayingVideo:(BOOL)playing {
    if (playing) {
        id item = [self currentVideoPlaybackItem];
        if (item) {
            g_currentPlayingItem = item;  // Track as active
        }
    }
    %orig;
}
%end
```

---

## 🎯 Tweak.x v8.2.64 Hook Map

| # | Target Class | Method | Purpose | Status |
|---|--------------|--------|---------|--------|
| 0 | `FBMemNewsFeedEdge` | `node` | Block ads | ✅ |
| 1 | `FBComponentCollectionViewDataSource` | `cellForItem` | Hide ad cells | ✅ |
| 2 | `FBComponentCollectionViewDataSource` | `willDisplay` | Hide ad cells | ✅ |
| 3 | `FBSnacksBucketsSeenStateManager` | `_sendSeenThreadIDsWithBucket:session:` | Block seen | ✅ |
| 4 | `FBSnacksBucketsSeenStateManager` | `_sendThreadIDsAsSeenInViewerSession:` | Block seen | ✅ |
| 5 | `FBSnacksBucketsSeenStateManager` | `markThreadsView...` | Block seen | ✅ |
| 6 | `FBSnacksMediaContainerView` | `initWithThread:...` | Story init | ✅ |
| 7 | `FBSnacksMediaContainerView` | `didMoveToWindow` | Story button | ✅ |
| 8 | `FBVideoOverlayPluginComponentBackgroundView` | `didLongPress:` | Newsfeed LP (legacy) | ⚠️ |
| 9 | `FBVideoPlaybackContainerView` | `initWithFrame:` | Newsfeed video | ✅ |
| 10 | `FBVideoPlaybackContainerView` | `layoutSubviews` | Newsfeed video | ✅ |
| 11 | `FBShortsSideBarView` | `didMoveToWindow` | Reels button | ✅ |
| 12 | `FBShortsSideBarView` | `layoutSubviews` | Reels button (fallback) | ✅ |
| 13 | `FBVideoPlaybackItem` | `HDPlaybackURL` | Capture URL | ✅ |
| 14 | `FBVideoPlaybackItem` | `SDPlaybackURL` | Capture URL | ✅ |
| 15 | `FBVideoPlaybackController` | `setPlaying:` | **Active playback** | ❌ **WRONG METHOD** |
| 16 | `FBVideoPlaybackController` | `setVideoItem:` | Capture item | ✅ |
| 17 | `FBVideoPlaybackController` | `currentVideoPlaybackItem` | Get item | ✅ |

---

## 🚀 Next Steps (v8.2.66)

1. Fix setPlaying: → setPlayingVideo: or setPlayingRequested:
2. Test on device
3. Build & ship v8.2.66

---

**Date:** Jun 26 2026  
**Version:** v8.2.64  
**Print this page for quick reference!**

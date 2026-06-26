# 📝 Findings Notes - FB 560.x Static Analysis

**Purpose:** Ghi chú tất cả findings từ quá trình phân tích tĩnh Facebook 560.x binary, để tham khảo sau này không phải tìm lại.

**Date:** Jun 26 2026  
**Binary:** FB 560.1.0 (FBSharedFramework 137MB, ARM64)  
**Tools Used:** strings, llvm-otool-18, rabin2 5.5.0, radare2 5.5.0, jtool (broken)

---

## 🎯 Quick Reference - Class Names

### Video Classes
| Class | Type | Purpose | Verified |
|-------|------|---------|----------|
| `FBVideoPlaybackContainerView` | UIView | Newsfeed video container | ✅ |
| `FBVideoPlaybackController` | NSObject | Video playback engine | ✅ |
| `FBVideoPlaybackItem` | NSObject | Video data with URLs | ✅ |
| `FBVideoPlaybackItemMetadata` | NSObject | Video metadata | ✅ |
| `FBVideoOverlayPluginComponentBackgroundView` | UIView | Video overlay background | ✅ |
| `FBVideoOverlayPluginComponentView` | UIView | Video overlay | ✅ |
| `FBShortsPlaybackController` | NSObject | Reels playback controller | ✅ |
| `FBShortsSideBarView` | UIView | Reels sidebar (Like/Comment/Share) | ✅ |

### Story Classes
| Class | Type | Purpose | Verified |
|-------|------|---------|----------|
| `FBSnacksMediaContainerView` | UIView | Story media container | ✅ |
| `FBSnacksNewVideoView` | UIView | Story video view | ✅ |
| `FBSnacksMediaPlayerManager` | NSObject | Story media manager | ✅ |
| `FBSnacksBucketsSeenStateManager` | NSObject | Story seen state | ✅ |

### Feed Classes
| Class | Type | Purpose | Verified |
|-------|------|---------|----------|
| `FBMemNewsFeedEdge` | NSObject | News feed edge model | ✅ |
| `FBComponentCollectionViewDataSource` | NSObject | Collection view data source | ✅ |
| `FBNewsFeedViewController` | UIViewController | News feed VC | ✅ |

---

## 📦 FBVideoPlaybackController - Properties & Ivars

**Class Address:** `0x06e4cfe8`

### Properties (6 total)
| Property Name | Type | Access | Description |
|---------------|------|--------|-------------|
| `controller` | id | read-write | Generic controller |
| `videoPlaybackController` | id | read-write | **Video playback controller** ⭐ |
| `videoController` | id | read-only | Video controller |
| `videoPlayerController` | id | read-write | Player controller |
| `warmedPlayer` | id | read-only | Pre-warmed player |
| `playbackController` | id | read-only | Playback controller |

### Raw Type Encodings (from radare2)
```
T@"FBVideoPlaybackController",W,N,V_controller
T@"FBVideoPlaybackController",R,W,N,V_videoPlaybackController
T@"FBVideoPlaybackController",R,N,V_videoController
T@"FBVideoPlaybackController",R,W,N,V_videoPlayerController
T@"FBVideoPlaybackController",R,N,V_warmedPlayer
T@"FBVideoPlaybackController",R,N,V_playbackController
```

### Methods
| Method | Selector Address | Description |
|--------|------------------|-------------|
| `currentVideoPlaybackItem` | `0x0578dc7a` | Get current video item ⭐ |
| `_currentVideoPlaybackItem` | `0x05ad7a1b` | Private getter |
| `setVideoItem:` | N/A | Set video item |
| `setPlayingVideo:` | `0x05751cc8` | Set playing video state |
| `setPlayingRequested:` | `0x057c27e4` | Set playing requested state |

### ⚠️ CRITICAL: setPlaying: DOES NOT EXIST
```
Found setPlaying selectors:
- pictureInPictureController(_:setPlaying:)  ← delegate method
- adapter: setPlaying - playing=              ← log string
- setPlayingVideo:                           ← different method
- setPlayingRequested:                       ← different method
- pictureInPictureController:setPlaying:     ← delegate method

NO direct setPlaying: (BOOL) on FBVideoPlaybackController!
```

### Recommended Alternatives
```objc
// Option 1: Hook setPlayingVideo:
static void hooked_setPlayingVideo(id self, SEL _cmd, BOOL playing) {
    if (playing) {
        // Track active video
    }
}

// Option 2: Hook setPlayingRequested:
static void hooked_setPlayingRequested(id self, SEL _cmd, BOOL playing) {
    if (playing) {
        // Track active video
    }
}

// Option 3: Hook currentVideoPlaybackItem
static id hooked_currentVideoPlaybackItem(id self, SEL _cmd) {
    id result = orig_currentVideoPlaybackItem ? ((id(*)(id, SEL))orig_currentVideoPlaybackItem)(self, _cmd) : nil;
    if (result) {
        g_currentPlayingItem = result;  // Track as active
    }
    return result;
}
```

---

## 📦 FBVideoPlaybackItem - Properties & Ivars

**Class Address:** `0x06e7a3a8`

### URL Properties (4 total)
| Property Name | Type | Attributes | Description |
|---------------|------|------------|-------------|
| `HDPlaybackURL` | NSURL | readonly, copy, nonatomic | **HD quality URL** ⭐ |
| `SDPlaybackURL` | NSURL | readonly, copy, nonatomic | **SD quality URL** ⭐ |
| `DashPlaybackURL` | NSURL | readonly, copy, nonatomic | DASH manifest URL |
| `HLSPlaybackURL` | NSURL | readonly, copy, nonatomic | HLS streaming URL |
| `sphericalPlaybackURL` | NSURL | readonly, copy, nonatomic | 360° video URL |
| `videoURL` | NSURL | readonly, copy, nonatomic | Generic video URL |

### Raw Type Encodings
```
T@"NSURL",R,C,N,V_HDPlaybackURL
T@"NSURL",R,C,N,V_SDPlaybackURL
T@"NSURL",R,C,N,V_DashPlaybackURL
T@"NSURL",R,C,N,V_HLSPlaybackURL
T@"NSURL",R,C,N,V_sphericalPlaybackURL
T@"NSURL",R,C,N,V_videoURL
```

### Other Properties (8 total)
| Property Name | Type | Description |
|---------------|------|-------------|
| `playbackItem` | id | Playback item |
| `playbackItemMetadata` | id | Metadata |
| `videoItem` | id | Video item |
| `liveInstrumentationConfig` | id | Live config |
| `postRollAdBreak` | id | Post-roll ad |
| `preRollAdBreak` | id | Pre-roll ad |
| `videoImfData` | id | IMF data |
| `watchProbability` | id | Watch probability |

### Methods
| Method | Description |
|--------|-------------|
| `HDPlaybackURL` | Get HD URL |
| `SDPlaybackURL` | Get SD URL |
| `DashPlaybackURL` | Get DASH URL |
| `HLSPlaybackURL` | Get HLS URL |
| `isSponsored` | Check if sponsored |
| `isVideoBroadcast` | Check if broadcast |
| `DashPlaylist` | Get DASH playlist |

---

## 📦 FBVideoPlaybackContainerView - Properties & Ivars

**Class Address:** `0x06e4d3a8`

### Properties (1 total)
| Property Name | Type | Description |
|---------------|------|-------------|
| `delegate` | id | Container view delegate ⭐ |
| `videoContainerView` | UIView | Video container subview |

### Inherited Methods (from UIView)
- `initWithFrame:`
- `layoutSubviews`
- `didMoveToWindow`

### Usage Pattern
```objc
// Hook initWithFrame: to add long press gesture
Class cls = objc_getClass("FBVideoPlaybackContainerView");
Method m = class_getInstanceMethod(cls, @selector(initWithFrame:));

// In handler, get controller via:
id controller = nil;
Ivar vpcIvar = class_getInstanceVariable(cls, "_videoPlaybackController");
if (vpcIvar) {
    controller = object_getIvar(container, vpcIvar);
}
```

---

## 📦 FBSnacksMediaContainerView - Story Container

### Init Method
```objc
- (id)initWithThread:(id)thread 
              bucket:(id)bucket 
   mediaViewDelegate:(id)mediaViewDelegate 
mediaViewGenerator:(id *)mediaViewGenerator 
           toolbox:(id)toolbox 
    shouldBlurMedia:(BOOL)shouldBlurMedia
```

### Ivar
| Name | Type | Description |
|------|------|-------------|
| `_mediaView` | UIView | Media view (photo/video) |

### MediaView Types
- `FBSnacksPhotoView` - photo story
- `FBSnacksNewVideoView` - video story

---

## 📦 FBSnacksNewVideoView - Story Video

### Properties
| Property | Type | Description |
|----------|------|-------------|
| `manager` | FBSnacksMediaPlayerManager | Media manager ⭐ |

### Usage Pattern
```objc
id mediaView = [container valueForKey:@"_mediaView"];
if ([mediaView isKindOfClass:NSClassFromString(@"FBSnacksNewVideoView")]) {
    id manager = [mediaView valueForKey:@"manager"];
    id item = [manager currentVideoPlaybackItem];
    NSURL *hdURL = [item HDPlaybackURL];
    NSURL *sdURL = [item SDPlaybackURL];
}
```

---

## 📦 FBSnacksMediaPlayerManager

### Methods
| Method | Description |
|--------|-------------|
| `currentVideoPlaybackItem` | Get current video item ⭐ |

---

## 📦 FBShortsSideBarView - Reels Sidebar

### Class Address: Found in FBSharedFramework

### Inherited Methods (from UIView)
- `initWithFrame:`
- `layoutSubviews`
- `didMoveToWindow`

### Structure
- Contains 5 `FDSTouchStateAnnouncingControl` children:
  1. Like
  2. Comment
  3. Share
  4. Save
  5. More

### Usage Pattern
```objc
// Hook didMoveToWindow (not layoutSubviews - timing issue)
Class cls = objc_getClass("FBShortsSideBarView");
Method m = class_getInstanceMethod(cls, @selector(didMoveToWindow));
```

---

## 📦 FBShortsPlaybackController

### Properties (1 total)
| Property | Type | Description |
|----------|------|-------------|
| `playbackController` | id | Reels playback controller |

### Raw Type Encoding
```
T@"FBShortsPlaybackController",R,N,V_playbackController
```

---

## 🔧 Protocols Discovered

### FBVideoPlaybackControlling
```
T@"<FBVideoPlaybackControlling>",N,W,VvideoPlaybackController
```

**Purpose:** Abstraction layer for video control  
**Implemented by:** FBVideoPlaybackController  
**Benefit:** Can hook protocol methods instead of direct class methods

---

## 🛠️ Tool Commands Reference

### strings
```bash
# Find class names
strings binary | grep "^FB" | sort -u

# Find specific class
strings binary | grep "FBVideoPlaybackController"

# Find methods
strings binary | grep "currentVideoPlaybackItem"
```

### llvm-otool-18
```bash
# List ObjC sections
llvm-otool-18 -l binary | grep -i objc

# Dump ObjC metadata
llvm-otool-18 -oV binary

# ⚠️ Only shows class list addresses, not details
```

### rabin2
```bash
# List symbols (BEST for class addresses)
rabin2 -s binary | grep "OBJC_CLASS_\$_ClassName"

# List all functions
rabin2 -s binary | grep "ClassName"

# Example:
rabin2 -s FBSharedFramework | grep "FBVideoPlaybackController"
# Output: 24417 0x06e4cfe8 _OBJC_CLASS_$_FBVideoPlaybackController
```

### radare2
```bash
# ⭐ BEST for property/ivar analysis
r2 -q -c "iz~ClassName" binary

# Find specific selector
r2 -q -c "izz~selector" binary

# Analyze all functions (slow for large binaries)
r2 -q -c "aa; afl" binary

# Examine struct at address
r2 -q -c "px 256 @ 0xADDRESS" binary

# Find cross-references
r2 -q -c "axt @ 0xADDRESS" binary
```

### jtool
```bash
# ❌ BROKEN - doesn't work with large ARM64 binaries
jtool -d objc binary
# Returns: no output
```

---

## 📊 Tool Effectiveness Ranking

| Rank | Tool | Use Case | Speed | Accuracy |
|------|------|----------|-------|----------|
| 1 | radare2 `iz` | Property/ivar extraction | Medium | ⭐⭐⭐⭐⭐ |
| 2 | rabin2 `-s` | Class symbols & addresses | Fast | ⭐⭐⭐⭐⭐ |
| 3 | strings | Quick class/method names | Very Fast | ⭐⭐⭐ |
| 4 | llvm-otool-18 | Section listing | Fast | ⭐⭐ |
| 5 | jtool | ObjC dumping | N/A | ❌ Broken |

---

## 🎓 Key Lessons Learned

### 1. Class Names Changed (260-307 → 560.x)
- `VideoContainerView` → `FBVideoPlaybackContainerView`
- Must use full class name with `FB` prefix

### 2. Ivar Names Changed
- `_controller` → `_videoPlaybackController`
- More specific names in 560.x

### 3. setPlaying: DOES NOT EXIST
- Original Glow used `setPlaying:` but that's on a different class
- In 560.x, use `setPlayingVideo:` or `setPlayingRequested:` instead
- Or hook `currentVideoPlaybackItem` getter

### 4. Properties vs Ivars
- In 560.x, many fields are **properties** (not just ivars)
- Properties have attributes: R (readonly), W (readwrite), C (copy), N (nonatomic)
- Use property accessors in Objective-C code

### 5. Protocol Layer
- `FBVideoPlaybackControlling` protocol exists
- Can hook protocol methods for cleaner code
- More stable than direct class methods

### 6. Tools Required
- jtool is outdated (v1.0 from 2018)
- rabin2 + radare2 are modern alternatives
- Always verify with multiple tools

---

## 🔍 Quick Analysis Scripts

### Find All Video Classes
```bash
strings FBSharedFramework | grep -E "^FB.*Video" | sort -u
```

### Find Class Address
```bash
rabin2 -s FBSharedFramework | grep "OBJC_CLASS_\$_ClassName"
```

### Get All Properties
```bash
r2 -q -c "iz~ClassName" FBSharedFramework | grep "V_" | sort -u
```

### Find Method Selector
```bash
r2 -q -c "izz~methodName" FBSharedFramework
```

---

## 📋 Tweak.x Implementation Map

### v8.2.64 Hook Targets
| Feature | Class | Method | Status |
|---------|-------|--------|--------|
| Ad blocking | `FBMemNewsFeedEdge` | `node` | ✅ Working |
| Story seen | `FBSnacksBucketsSeenStateManager` | 3 methods | ✅ Working |
| Story download | `FBSnacksMediaContainerView` | `didMoveToWindow` | ✅ Fixed v8.2.64 |
| Newsfeed video | `FBVideoPlaybackContainerView` | `initWithFrame:` | ✅ Fixed v8.2.64 |
| Reels button | `FBShortsSideBarView` | `didMoveToWindow` | ✅ Fixed v8.2.64 |
| Reels playback | `FBVideoPlaybackController` | `setPlaying:` | ❌ **WRONG METHOD** |

### ⚠️ CRITICAL: Fix Needed in v8.2.66

**Current code (v8.2.60-64):**
```objc
SEL setPlayingSel = sel_registerName("setPlaying:");
if (class_respondsToSelector(cls, setPlayingSel)) {
    // Hook setPlaying: - DOES NOT WORK!
}
```

**Fix options:**
1. Use `setPlayingVideo:` instead
2. Use `setPlayingRequested:` instead  
3. Use `currentVideoPlaybackItem` getter instead

---

## 📚 Related Files

- `STATIC_ANALYSIS.md` - Initial static analysis (strings + llvm-otool)
- `JTOOL_ANALYSIS.md` - jtool + llvm-otool analysis
- `RABIN2_RADARE2_ANALYSIS.md` - rabin2 + radare2 analysis
- `V8.2.64_SUMMARY.md` - Current version summary
- `TWEAK_X_GUIDE.md` - Tweak.x structure guide
- `tools/rabin2_analyze.py` - Automated property extraction
- `tools/quick_analyze.py` - Quick class analysis
- `tools/find_methods.py` - Method finder

---

## 🔄 Update Log

- **v8.2.64**: Confirmed all key classes exist, fixed Story/Newsfeed/Reels hooks
- **v8.2.66 (TODO)**: Fix setPlaying: → setPlayingVideo: / setPlayingRequested:

---

**Last Updated:** Jun 26 2026  
**Version:** v8.2.64  
**Purpose:** Quick reference for future development

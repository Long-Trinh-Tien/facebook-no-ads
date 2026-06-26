# Static Analysis Report - Facebook 560.x Video/Story/Reels Classes

**Date:** Jun 26 2026  
**Binary:** FB 560.1.0 (facebook.ipa)  
**Tool:** llvm-otool-18 + strings

---

## 📊 Key Findings

### 1. **Newsfeed Video - Class Name Changed**

**Original Glow (FB 260-307):**
- `VideoContainerView` 
- Has `controller` property

**Current (FB 560.x):**
- `FBVideoPlaybackContainerView` ✅ EXISTS
- Has `_videoPlaybackController` ivar
- Has `controller` property (from `T@"FBVideoPlaybackController",R,W,N,V_controller`)

**Fix:** Change hook target from `VideoContainerView` → `FBVideoPlaybackContainerView`

---

### 2. **Video Playback Controller**

**Class:** `FBVideoPlaybackController` ✅ EXISTS

**Key methods:**
- `currentVideoPlaybackItem` → returns `FBVideoPlaybackItem`
- `setPlaying:` → BOOL parameter (for tracking active playback)

**Key ivars:**
- `_videoPlaybackController` (on container view)

---

### 3. **Video Playback Item**

**Class:** `FBVideoPlaybackItem` ✅ EXISTS

**URL methods (all exist):**
- `HDPlaybackURL` (capital HD) ✅
- `SDPlaybackURL` (capital SD) ✅
- `DashPlaybackURL` ✅
- `HLSPlaybackURL` ✅
- `hdPlaybackURL` (lowercase) ✅
- `sdPlaybackURL` (lowercase) ✅
- `dashPlaybackURL` ✅
- `hlsPlaybackURL` ✅

**Other methods:**
- `isSponsored` ✅
- `isVideoBroadcast` ✅

---

### 4. **Story (Snacks) Classes**

**Container:**
- `FBSnacksMediaContainerView` ✅ EXISTS
- Protocol: `FBSnacksMediaContainerViewProtocol`

**Video view:**
- `FBSnacksNewVideoView` ✅ EXISTS
- Has `manager` property (returns `FBSnacksMediaPlayerManager`)

**Manager:**
- `FBSnacksMediaPlayerManager` ✅ EXISTS
- Has `currentVideoPlaybackItem` method

**Issue:** Button positioning uses `window` parameter which can be nil → use `[UIApplication sharedApplication].keyWindow`

---

### 5. **Reels (Shorts) Classes**

**Controller:**
- `FBShortsPlaybackController` ✅ EXISTS
- `FBVideoPlaybackController` ✅ ALSO USED

**Issue:** `setPlaying:` hook needs to target the correct class. Log shows it's hooking `FBMemModelObjectUnknownSelectorHandler` instead of `FBVideoPlaybackController`.

---

## 🔧 Required Fixes

### Fix 1: Newsfeed Video
```objc
// BEFORE (wrong class name)
Class videoContainerCls = objc_getClass("VideoContainerView");

// AFTER (correct class name)
Class videoContainerCls = objc_getClass("FBVideoPlaybackContainerView");
```

### Fix 2: Story Button Positioning
```objc
// BEFORE (window can be nil)
btn.frame = CGRectMake(window.frame.size.width - 60, window.frame.size.height - 120, 44, 44);

// AFTER (use keyWindow)
UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
btn.frame = CGRectMake(keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120, 44, 44);
```

### Fix 3: Reels setPlaying: Hook
```objc
// Need to verify which class actually has setPlaying:
// Log shows: [dl/reel] hooked setPlaying: on FBMemModelObjectUnknownSelectorHandler
// Should be: FBVideoPlaybackController or FBShortsPlaybackController
```

---

## 📋 Class Hierarchy (Inferred)

```
Newsfeed Video:
  FBVideoPlaybackContainerView
    └─ _videoPlaybackController (ivar) → FBVideoPlaybackController
         └─ currentVideoPlaybackItem → FBVideoPlaybackItem
              ├─ HDPlaybackURL
              ├─ SDPlaybackURL
              └─ isSponsored

Story:
  FBSnacksMediaContainerView
    └─ _mediaView (ivar) → FBSnacksNewVideoView
         └─ manager → FBSnacksMediaPlayerManager
              └─ currentVideoPlaybackItem → FBVideoPlaybackItem

Reels:
  FBShortsViewerOverlayComponentView
    └─ FBShortsSideBarView (action buttons)
    └─ FBVideoPlaybackController (or FBShortsPlaybackController)
         └─ currentVideoPlaybackItem → FBVideoPlaybackItem
```

---

## ✅ Verified Methods (Exist in 560.x)

| Class | Method | Status |
|-------|--------|--------|
| `FBVideoPlaybackContainerView` | (class exists) | ✅ |
| `FBVideoPlaybackController` | `currentVideoPlaybackItem` | ✅ |
| `FBVideoPlaybackController` | `setPlaying:` | ✅ (need correct target) |
| `FBVideoPlaybackItem` | `HDPlaybackURL` | ✅ |
| `FBVideoPlaybackItem` | `SDPlaybackURL` | ✅ |
| `FBVideoPlaybackItem` | `isSponsored` | ✅ |
| `FBSnacksMediaContainerView` | (class exists) | ✅ |
| `FBSnacksNewVideoView` | `manager` | ✅ |
| `FBSnacksMediaPlayerManager` | `currentVideoPlaybackItem` | ✅ |

---

## 🎯 Next Steps

1. ✅ Update `findVideoContainerClass()` to search for `FBVideoPlaybackContainerView`
2. ✅ Fix story button positioning to use `keyWindow`
3. ⚠️ Verify `setPlaying:` target class (may need runtime check)
4. Build and test

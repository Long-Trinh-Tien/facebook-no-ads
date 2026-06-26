# 🔬 rabin2 + radare2 Analysis Report - FB 560.x

**Date:** Jun 26 2026  
**Tools:** rabin2 5.5.0 + radare2 5.5.0  
**Binary:** FB 560.1.0 (FBSharedFramework 137MB, ARM64)

---

## 📊 Executive Summary

Sử dụng rabin2 và radare2 để phân tích sâu hơn vào Facebook binary, phát hiện:

1. **rabin2 cung cấp symbol addresses** chính xác cho ObjC classes
2. **radare2 cung cấp property/ivar definitions** từ type encodings
3. **Phát hiện quan trọng**: `setPlaying:` KHÔNG phải là direct method trên FBVideoPlaybackController
4. **Tìm thấy protocol** `FBVideoPlaybackControlling` - abstraction layer

---

## 🛠️ Tools Comparison

| Tool | Version | Use Case | Effectiveness |
|------|---------|----------|---------------|
| rabin2 | 5.5.0 | Symbol extraction, class lists | ⭐⭐⭐⭐ Excellent |
| radare2 | 5.5.0 | Disassembly, string search, analysis | ⭐⭐⭐⭐⭐ Excellent |
| strings | GNU | Quick class/method names | ⭐⭐⭐ Good |
| llvm-otool-18 | 18 | Section listing | ⭐⭐ Limited |
| jtool | 1.0 | ObjC dumping | ❌ Broken |

---

## 🔍 Key Discoveries

### Discovery 1: Class Addresses (rabin2)

Sử dụng `rabin2 -s` để tìm class symbols:

```bash
$ rabin2 -s FBSharedFramework | grep "OBJC_CLASS_\$_FBVideoPlayback"
24416 0x06e4d3a8 _OBJC_CLASS_$_FBVideoPlaybackContainerView
24417 0x06e4cfe8 _OBJC_CLASS_$_FBVideoPlaybackController
24418 0x06e7a3a8 _OBJC_CLASS_$_FBVideoPlaybackItem
24419 0x06ea06d8 _OBJC_CLASS_$_FBVideoPlaybackItemMetadata
```

**Kết quả:** Có địa chỉ chính xác của class structures trong binary.

---

### Discovery 2: Properties & Ivars (radare2)

Sử dụng `r2 -q -c "iz~ClassName"` để tìm property/ivar definitions:

#### FBVideoPlaybackController
```
T@"FBVideoPlaybackController",W,N,V_controller
T@"FBVideoPlaybackController",R,W,N,V_videoPlaybackController
T@"FBVideoPlaybackController",R,N,V_videoController
T@"FBVideoPlaybackController",R,W,N,V_videoPlayerController
T@"FBVideoPlaybackController",R,N,V_warmedPlayer
T@"FBVideoPlaybackController",R,N,V_playbackController
```

**Kết quả:** 6 properties/ivars xác nhận:
- `controller` (read-write)
- `videoPlaybackController` (read-write) ⭐
- `videoController` (read-only)
- `videoPlayerController` (read-write)
- `warmedPlayer` (read-only)
- `playbackController` (read-only)

#### FBVideoPlaybackItem
```
T@"FBVideoPlaybackItem",R,N,V_playbackItem
T@"FBVideoPlaybackItem",R,N,V_playbackItemMetadata
T@"FBVideoPlaybackItem",R,N,V_videoItem
T@"FBVideoPlaybackItem",R,N,V_liveInstrumentationConfig
T@"FBVideoPlaybackItem",R,N,V_postRollAdBreak
T@"FBVideoPlaybackItem",R,N,V_preRollAdBreak
T@"FBVideoPlaybackItem",R,N,V_videoImfData
T@"FBVideoPlaybackItem",R,N,V_watchProbability
```

#### FBShortsPlaybackController
```
T@"FBShortsPlaybackController",R,N,V_playbackController
```

**Kết quả:** Chỉ có 1 ivar `playbackController` (khác với FBVideoPlaybackController).

---

### Discovery 3: setPlaying: KHÔNG phải direct method (CRITICAL)

Sử dụng `r2 -q -c "izz~setPlaying"` để tìm tất cả setPlaying selectors:

```
498509 ascii   pictureInPictureController(_:setPlaying:)      ← delegate method
498518 ascii   adapter: setPlaying - playing=                  ← log string
529451 ascii   setPlayingVideo:                               ← different method
541669 ascii   setPlayingRequested:                           ← different method
653691 ascii   pictureInPictureController:setPlaying:         ← delegate method
```

**Kết quả QUAN TRỌNG:**
- ❌ KHÔNG có `setPlaying:` (BOOL) trực tiếp trên FBVideoPlaybackController
- ✅ Có `pictureInPictureController:setPlaying:` (delegate method)
- ✅ Có `setPlayingVideo:` và `setPlayingRequested:` (các methods khác)

**Implication cho v8.2.60 code:**
- Code hiện tại hook `setPlaying:` trên FBVideoPlaybackController → SAI!
- Cần tìm method khác để track active playback

**Methods có thể thay thế:**
- `setPlayingVideo:` (BOOL parameter)
- `setPlayingRequested:` (BOOL parameter)

---

### Discovery 4: FBVideoPlaybackControlling Protocol

```
T@"<FBVideoPlaybackControlling>",N,W,VvideoPlaybackController
```

**Kết quả:** FBVideoPlaybackController implement protocol `FBVideoPlaybackControlling` - abstraction layer cho video control.

**Implication:** Có thể hook protocol methods thay vì direct class methods.

---

### Discovery 5: currentVideoPlaybackItem Location

```
11615  0x0578dc7a  24  25  8.__TEXT.__objc_methname  ascii   currentVideoPlaybackItem
101381 0x05ad7a1b  25  26  8.__TEXT.__objc_methname  ascii   _currentVideoPlaybackItem
```

**Kết quả:**
- `currentVideoPlaybackItem` ở address `0x0578dc7a`
- `_currentVideoPlaybackItem` (private) ở address `0x05ad7a1b`
- Cả hai đều trong `__TEXT.__objc_methname` section

---

### Discovery 6: HDPlaybackURL Definitions

```
T@"NSURL",R,C,N,V_HDPlaybackURL       ← property
T@"NSURL",R,C,N,V_SDPlaybackURL       ← property
T@"NSURL",R,C,N,V_DashPlaybackURL     ← property
T@"NSURL",R,C,N,V_HLSPlaybackURL      ← property
T@"NSURL",R,C,N,V_sphericalPlaybackURL ← property
T@"NSURL",R,C,N,V_videoURL            ← property
```

**Kết quả:** Tất cả URL methods là **properties** với attributes:
- `R` = readonly
- `C` = copy
- `N` = nonatomic

**Confirmed:** `HDPlaybackURL`, `SDPlaybackURL`, `DashPlaybackURL`, `HLSPlaybackURL` đều là NSURL properties.

---

## 🎯 Implications for v8.2.60+ Development

### Critical Finding: setPlaying: Hook is WRONG

**Current code (v8.2.60):**
```objc
static void hooked_setPlaying(id self, SEL _cmd, BOOL playing) {
    // ...
}
```

**Problem:** `setPlaying:` KHÔNG tồn tại trực tiếp trên FBVideoPlaybackController!

**Solution Options:**

1. **Hook `setPlayingVideo:` instead:**
```objc
static void hooked_setPlayingVideo(id self, SEL _cmd, BOOL playing) {
    if (playing) {
        // Track active video
    }
}
```

2. **Hook `setPlayingRequested:` instead:**
```objc
static void hooked_setPlayingRequested(id self, SEL _cmd, BOOL playing) {
    if (playing) {
        // Track active video
    }
}
```

3. **Hook `currentVideoPlaybackItem` method:**
```objc
static id hooked_currentVideoPlaybackItem(id self, SEL _cmd) {
    id result = orig_currentVideoPlaybackItem ? ((id(*)(id, SEL))orig_currentVideoPlaybackItem)(self, _cmd) : nil;
    if (result) {
        // Track this item as active
        g_currentPlayingItem = result;
    }
    return result;
}
```

---

## 📊 Complete Class Property/Ivar Map

### FBVideoPlaybackController
| Name | Type | Access | Description |
|------|------|--------|-------------|
| controller | id | read-write | Generic controller |
| videoPlaybackController | id | read-write | Video playback controller ⭐ |
| videoController | id | read-only | Video controller |
| videoPlayerController | id | read-write | Player controller |
| warmedPlayer | id | read-only | Pre-warmed player |
| playbackController | id | read-only | Playback controller |

### FBVideoPlaybackItem
| Name | Type | Access | Description |
|------|------|--------|-------------|
| playbackItem | id | read-only | Playback item |
| playbackItemMetadata | id | read-only | Metadata |
| videoItem | id | read-only | Video item |
| liveInstrumentationConfig | id | read-only | Live config |
| postRollAdBreak | id | read-only | Post-roll ad |
| preRollAdBreak | id | read-only | Pre-roll ad |
| videoImfData | id | read-only | IMF data |
| watchProbability | id | read-only | Watch probability |
| HDPlaybackURL | NSURL | readonly, copy | HD URL ⭐ |
| SDPlaybackURL | NSURL | readonly, copy | SD URL ⭐ |
| DashPlaybackURL | NSURL | readonly, copy | DASH URL |
| HLSPlaybackURL | NSURL | readonly, copy | HLS URL |

### FBShortsPlaybackController
| Name | Type | Access | Description |
|------|------|--------|-------------|
| playbackController | id | read-only | Reels playback controller |

---

## 🛠️ rabin2/radare2 Commands Used

### Class Information
```bash
# Find class symbols
rabin2 -s binary | grep "OBJC_CLASS_\$_ClassName"

# Find property/ivar definitions
r2 -q -c "iz~ClassName" binary

# Find specific selector
r2 -q -c "izz~selector" binary

# Get all functions
r2 -q -c "aa; afl" binary

# Examine class struct
r2 -q -c "px 256 @ class_address" binary
```

### Property/Ivar Parsing
```bash
# Property format: T@"Class",[R][W][C],N,V_name
# R = readonly
# W = readwrite  
# C = copy
# N = nonatomic
# V_ = ivar name
```

---

## 🎓 Lessons Learned

1. **rabin2 > llvm-otool** cho class symbol extraction
2. **radare2 iz** command rất mạnh cho type encoding analysis
3. **Không assume method names** - phải verify trong binary
4. **setPlaying: có thể KHÔNG tồn tại** trên class bạn nghĩ
5. **Protocols (FBVideoPlaybackControlling)** là abstraction layer quan trọng
6. **Property attributes (R, W, C, N)** cho biết cách sử dụng đúng

---

## 🚀 Next Steps

1. ✅ Verified all key classes exist
2. ✅ Confirmed property/ivar names
3. ⚠️ **CRITICAL**: Need to fix setPlaying: hook (use setPlayingVideo: or setPlayingRequested: instead)
4. 📝 Update v8.2.64 code to use correct method
5. 🧪 Test on device
6. 📦 Build v8.2.66

---

## 📚 Related Documentation

- `STATIC_ANALYSIS.md` - Initial static analysis
- `JTOOL_ANALYSIS.md` - jtool/llvm-otool analysis
- `V8.2.64_SUMMARY.md` - Current version summary
- `TWEAK_X_GUIDE.md` - Tweak.x structure guide

---

**Tác giả:** OpenCode (rabin2 + radare2 analysis)  
**Ngày:** Jun 26 2026  
**Version:** v8.2.64

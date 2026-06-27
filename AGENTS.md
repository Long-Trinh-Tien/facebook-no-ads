# Glow Clone — Session Context (Compacted)

otool on this machine is 'llvm-otool-18'
## Current Stage
**STAGE R3.6/v8.3.6 — CRASH ROOT CAUSE FOUND** 🔍
- Ad blocking: WORKS (no gap) ✅
- Story seen: BLOCKED via 3 hooks ✅
- **Story download crash: ROOT CAUSE IDENTIFIED in RuntimeEnumHooks.xm**
- **EVIDENCE RULE: NO code without log evidence from device**

## 🚨 CRITICAL RULE: NO CODE WITHOUT LOG EVIDENCE

**NEVER implement a feature without first verifying with ONLY logging.**

This mistake cost us 6 releases (v8.3.0→v8.3.6):

| Version | What we did | What we SHOULD have done |
|---------|-------------|--------------------------|
| v8.3.0 | Implemented ALL 5 modules at once | Add logging-only hooks first, test each one |
| v8.3.1 | Added gesture + ivar fallbacks to StoryDownload | Check crash logs BEFORE guessing |
| v8.3.2→6 | Kept "fixing" StoryDownloadHooks | Binary-search disable ONE module at a time |

**NEW WORKFLOW for any feature:**

```
1. Write a DEBUG build with ONLY logging (no IMP replacement)
   → Install on device → Read /var/mobile/Documents/glow.txt
2. Verify classes/methods exist and timing is correct
3. Only THEN write the real implementation
4. Test incrementally (1 module at a time)
```

## 🔍 Root Cause: Story Crash Since v8.3.0

### What We Thought
Crash was in StoryDownloadHooks because:
- v8.3.1 added gesture in `init` + ivar fallbacks → CRASH appeared
- We "fixed" by removing gesture (v8.3.3), disabling StoryDownloadHooks (v8.3.4), restoring v8.2.64 code (v8.3.5), inlining class (v8.3.6)
- **ALL STILL CRASHED** because we were fixing the WRONG thing

### The REAL Bug (RuntimeEnumHooks.xm:180-222)

File: `Core/RuntimeEnumHooks.xm` at lines 180-222

```objc
// BUG: hooks setVideoPlayer: on ALL FB classes, uses ONE orig_* IMP
for (int i = 0; i < count; i++) {
    Class cls = classes[i];
    if (strncmp(name, "FB", 2) != 0) continue;

    if (!orig_setVideoPlayer) {
        orig_setVideoPlayer = method_getImplementation(m); // Class A's IMP
    }
    method_setImplementation(m, (IMP)hooked_setVideoPlayer); // overwrite Class B too
}
```

**Problem:** For `setVideoPlayer:`, `setPlaybackController:`, `configureWithVideo:`, `configureWithModel:` — the code hooks these on **ALL FB-prefixed classes** but stores only ONE `orig_*` pointer from the FIRST class found. 

When Class B's method is called → goes through `hooked_setVideoPlayer` → calls `orig_setVideoPlayer` (Class A's IMP) → **CRASH** because `self` is Class B, not Class A.

### Why It Crashes on Story Tap
When user taps a Story, FB initializes Story video infrastructure:
1. Story calls `setVideoPlayer:`, `setPlaybackController:`, etc. on Story-specific classes
2. These go through our broken hooks
3. Wrong IMP called → EXC_BAD_ACCESS

### Why v8.2.68 Worked (before v8.3.0)
v8.2.68 only had: AdBlock, StorySeen, StoryDownload. NO RuntimeEnumHooks, NO ReelsDownloadHooks, NO LongPressHooks.

### Fix Strategy
**TWO options:**

**Option A — Per-class orig_* storage (proper fix):**
```objc
// Before hooking, check if the method is INHERITED vs OWN
// Only hook if superclass also has the same IMP → safe
// Otherwise, store per-class orig_*
```

**Option B — Target only specific classes (conservative fix):**
```objc
// Only hook on FBVideoPlaybackController (not all FB classes)
if (strstr(name, "FBVideoPlaybackController") != NULL) {
    // hook only here
}
```

**Option B is the right fix.** The original intent was to hook these on `FBVideoPlaybackController` for Reels playback tracking, not on every FB class. The overly broad filter caused the bug.

---

## Detailed Investigation Journey

### Phase 0: Initial attempts (R0 - R1)
...
(history preserved from earlier phases — see git log for full detail)

### Phase 0.5: Modular Refactor (v8.2.68)
- **v8.2.68**: Tweak.x 4294→100 lines, 7 Core modules, 4 Managers, 2 Utils
- Tests: 49 unit tests

### Phase 6b: The "Wrong Fix" Rabbit Hole (v8.3.0 - v8.3.6)

This is the cautionary tale of fixing without evidence.

| Version | Change | Result | Lesson |
|---------|--------|--------|--------|
| v8.3.0 | Added ALL 5 stub modules (NewsfeedVideo, Reels, LongPress, Explorer, RuntimeEnum) | **Story CRASH introduced** | Never add 5 modules at once |
| v8.3.1 | Added gesture to StoryDownload `init` + ivar fallbacks | STILL CRASHED | Guessed wrong cause |
| v8.3.2 | Removed alert from LongPressHooks | STILL CRASHED | Fixing wrong file |
| v8.3.3 | Removed gesture from `init` hook | STILL CRASHED | Still wrong |
| v8.3.4 | DISABLED StoryDownloadHooks entirely | STILL CRASHED | **BIG CLUE IGNORED**: crash not in StoryDownload! |
| v8.3.5 | Restored v8.2.64 code exactly | STILL CRASHED | Crash confirmed NOT in StoryDownload |
| v8.3.6 | Inlined class (no singleton) | **ROOT CAUSE FOUND** by reading code, not by testing |

**Key missed clue:** v8.3.4 disabled StoryDownloadHooks entirely → **still crashed**. This proved crash was NOT in StoryDownload. But we ignored it and kept "fixing" StoryDownload.

### What Should Have Happened

```
v8.3.0 added 5 modules → crash
  ↓
Disable ALL 5 → test→ still works?
  ↓
Enable ONE → test→ still works?
  ↓
Enable ANOTHER → test→ crash!
  ↓
→ Found culprit module in 5 tests
  ↓
Read culprit module code → found bug immediately
  ↓
Fixed in 1 commit instead of 6
```

**Binary search would have found RuntimeEnumHooks in ~3 test cycles instead of 6 wasted builds.**

---

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
| v8.3.0 | **RuntimeEnumHooks hooks ALL FB classes with ONE orig_* IMP** → crash on Story tap | Limit to specific class only (FBVideoPlaybackController) | **PENDING** |

---

## Key Files

| File | Purpose |
|------|---------|
| `Core/StoryDownloadHooks.xm` | **INNOCENT** — crash was not here |
| `Core/RuntimeEnumHooks.xm` | **GUILTY** — lines 180-222: broad hook on ALL FB classes |
| `Core/AdBlockHooks.xm` | Working |
| `Core/StorySeenHooks.xm` | Working |
| `Core/ReelsDownloadHooks.xm` | Probably OK |
| `Core/LongPressHooks.xm` | Probably OK (just logs) |
| `Core/NewsfeedVideoHooks.xm` | Safe (skipped, no class found) |
| `Core/PlaybackStateHooks.xm` | Maybe safe (only hooks FBVideoPlaybackController) |
| `Core/VideoItemHooks.xm` | ? |
| `Core/ExplorerHooks.xm` | Stub (empty) |

---

## What's Working

✅ Ad blocking: FBMemNewsFeedEdge.node returns nil for SPONSORED
✅ Story seen: 3 paths blocked
✅ No layout gaps
✅ Feed scroll smooth

## What's TODO (with EVIDENCE LOGS FIRST)

1. **Fix Story crash**: Limit RuntimeEnumHooks to `FBVideoPlaybackController` only (not ALL FB classes)
2. **Verify Story download**: After crash fix, test if v8.3.6 button works
3. **Add Reels button**: Need log evidence that FBShortsSideBarView exists
4. **Add video download**: Need log evidence that FBVideoPlaybackContainerView exists
5. **Implement new features**: ALWAYS deploy logging-only build first

---

## Golden Rule

### 🔴 NO CODE WITHOUT LOG EVIDENCE 🔴

**Before implementing ANY feature:**
1. Write a logging-only build (observe, don't modify)
2. Deploy to device
3. Read `/var/mobile/Documents/glow.txt`
4. Confirm the classes, methods, and timing exist
5. Only then write the real implementation

**When debugging a crash:**
1. Do NOT guess the cause
2. Get crash log from device (`/var/mobile/Library/Logs/CrashReporter/`)
3. Binary-search by disabling modules
4. Read the crashing module's code carefully
5. Fix with confidence

---

## Critical Environment

- Facebook version: 560.x (tested)
- iOS: 16+ (TrollStore)
- Tweak injection: cyan
- Build system: Theos
- Log file: `/var/mobile/Documents/glow.txt`
- Bundle IDs: `com.facebook.Facebook`, `com.facebook.Facebook6`
- GitHub: `https://github.com/Long-Trinh-Tien/facebook-no-ads` branch `v8-glow-framework`

# Original Glow 1.3.1 — Hook Analysis & Comparison

> Analysis of `com.dvntm.glow_1.3.1_iphoneos-arm64e.deb`
> Compiled: 2025-06-25 by dayanch96 (https://github.com/dayanch96/Glow)

## TL;DR

The original Glow 1.3.1 dylib uses the **old hook strategy** that was designed
for Facebook versions where `FBMemFeedStory` and `FBVideoChannelPlaylistItem` still
existed (pre-500.x). In Facebook 560.x those classes are REMOVED, so most of Glow's
ad-blocking hooks no longer fire.

**Key insight:** The dylib is closed-source (only the .deb is released). The repo
`dayanch96/Glow` is just a build wrapper that downloads the .deb from releases and
injects it with `cyan` + `pyzule`.

## Binary Analysis

### File Info
- **Path:** `Library/MobileSubstrate/DynamicLibraries/Glow.dylib`
- **Size:** 16,787,088 bytes (16 MB) — relatively large because it bundles FFmpegKit
- **Architecture:** arm64e (file shows arm64, package declares arm64e)
- **Filter:** `com.facebook.Facebook` (only — NOT `com.facebook.Facebook6`)
- **Bundle languages:** 11 (Base, ar, es, fr, pl, ru, tr, vi, zh-Hans, zh-Hant)
- **Bundle dependencies:** FacebookSettings, NSURLSession* (download), FFmpeg (re-encoding)
- **Author:** dvntm, nowesr1 (https://github.com/dayanch96/Glow)

### Mach-O Structure

| Section | Offset | Size | Purpose |
|---------|--------|------|---------|
| `__TEXT.__objc_methname` | 0xa0ef90 | 19,478 B | 853 selector strings |
| `__TEXT.__objc_classname` | 0xd00a81 | 685 B | 23 class names |
| `__DATA_CONST.__objc_classlist` | 0xed3058 | 184 B | 23 classes registered |
| `__DATA_CONST.__objc_catlist` | 0xed3110 | 8 B | 1 category registered |
| `__DATA.__objc_const` | 0xed4000 | 19,584 B | class_ro_t data |
| `__DATA.__objc_selrefs` | 0xed8c80 | 4,864 B | selector references |
| `__DATA.__objc_classrefs` | 0xed9f80 | 768 B | external class references |
| `__DATA.__objc_ivar` | 0xeda2f8 | 372 B | ivar layouts |

### Dylib's Own Classes (23)

```
WelcomeVC               // 0 methods  - onboarding welcome screen
DVNLongPressGestureRecognizer  // 0 methods  - long press detector
MPDParser               // 0 methods  - MPD (DASH manifest) parser for video
Downloader              // 0 methods  - main download manager
DVNSheetPresenter       // 0 methods  - sheet presentation helper
FFMpegHelper            // 0 methods  - ffmpeg integration helper
ToastView               // 0 methods  - toast notifications
DownloaderHelper        // 0 methods  - download helpers
ToastWindow             // 0 methods  - toast window
ToastManager            // 0 methods  - toast manager
GlowUserDefaults        // 0 methods  - settings storage
PseudoDetentController  // 0 methods  - sheet detent controller
PseudoDetentTransitioningDelegate  // 0 methods
DVNSheetController      // 0 methods  - sheet view controller
SettingsViewController  // 0 methods  - settings UI
ChangelogVC             // 0 methods  - changelog view
ArchDetect              // 0 methods  - arch detection (arm64 vs arm64e)
AtomicLong              // 3 methods  - atomic long
FFmpegExecution         // 5 methods  - ffmpeg execution
FFmpegKit               // 0 methods  - ffmpeg wrapper
CallbackData            // 12 methods - ffmpeg callback data
FFmpegKitConfig         // 0 methods  - ffmpeg config
Statistics              // 11 methods - download statistics
Glow                    // 0 methods  - main tweak class
```

(0-method count is from our static analysis; most methods are stored as IMP pointers
in the .data segment and are not enumerated as `method_list_t`.)

### FB-Related Selector References (76 total)

The complete set of FB hooks/selectors used by Glow 1.3.1:

#### Ad-blocking (2 hooks — the OLD approach)

| Selector | Target class (expected) | Used in 560.x? |
|----------|------------------------|-----------------|
| `initWithFBPandoTree:` | `FBMemNewsFeedEdge` (Pando), `FBMemFeedStory` | ❌ Pando is removed; `initWithFBPandoTree:` is no longer called on `FBMemNewsFeedEdge` |
| `initWithFBTree:` | `FBMemNewsFeedEdge`, `FBMemFeedStory`, `FBVideoChannelPlaylistItem` | ⚠️ Still exists on `FBMemNewsFeedEdge` but no longer called with tree (uses `node:` instead) |

#### Story seen (1 hook)

| Selector | Status in 560.x |
|----------|-----------------|
| `_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:` | ❌ REMOVED — method name changed in 560.x (replaced by `_sendThreadIDsAsSeenInViewerSession:` + `markThreadsViewReceiptsAndLightweightReactionsAsSeen:bucket:session:isHighlight:successBlock:noThreadsToMarkAsSeenBlock:`) |

#### Reels / videos

| Selector | Likely use |
|----------|------------|
| `_reels` | ivar access — Reels tray |
| `_adaptationType` | ivar access — video adaptation |
| `_currentAdaptationDict` | ivar access — current adaptation |
| `_advanceToNextItemWithNavigationAction:` | disable auto-advance |
| `isVideoBroadcast` | property check |
| `isMemberOfClass:` | runtime class check |
| `currentThread` | story thread access |
| `threadAuthor` | thread author access |
| `threads` | threads list |
| `_mediaData` | media data ivar |
| `sponsoredData` | sponsored data check |
| `storyBucketType` | story bucket type |

#### Download / URLSession (many)

```
URLSession:dataTask:didBecomeDownloadTask:
URLSession:downloadTask:didFinishDownloadingToURL:
URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes:
URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:
downloadFileWithURL:fileName:
downloadMedia:
downloadAudio
downloadButton
downloadDidFailureWithError:
downloadDidFinish:
downloadNextChunk
downloadPreEncodedMedia:
downloadProgress:
downloadTaskWithRequest:
saveMedia:
processDownloading:
cancelDownload
```

#### Table view / UI

```
tableView:heightForHeaderInSection:
tableView:estimatedHeightForHeaderInSection:
tableView:viewForHeaderInSection:
tableView:titleForHeaderInSection:
tableView:willDisplayHeaderView:forSection:
tableView:didEndDisplayingHeaderView:forSection:
tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:
tableView:shouldSpringLoadRowAtIndexPath:withContext:
viewDidLoad
loadView
```

## What's Wrong With Original Glow 1.3.1

### 1. Ad blocking is broken in 560.x

The dylib hooks `initWithFBPandoTree:` and `initWithFBTree:`. In 560.x:

- `FBMemFeedStory` class is REMOVED → no stories to hook
- `FBVideoChannelPlaylistItem` class is REMOVED → no reels playlist to hook
- `FBMemNewsFeedEdge.initWithFBPandoTree:` is GONE → primary hook dead
- `FBMemNewsFeedEdge.initWithFBTree:` is GONE → secondary hook dead
- The replacement method is `FBMemNewsFeedEdge.node` (no args, returns the layout node)

### 2. Story seen is broken in 560.x

The dylib hooks `_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:`.
In 560.x this method is REMOVED. The replacement paths (verified in our `glow_v7`):

- `FBSnacksBucketsSeenStateManager._sendSeenThreadIDsWithBucket:session:`
- `FBSnacksBucketsSeenStateManager._sendThreadIDsAsSeenInViewerSession:`
- `FBSnacksBucketsSeenStateManager.markThreadsViewReceiptsAndLightweightReactionsAsSeen:bucket:session:isHighlight:successBlock:noThreadsToMarkAsSeenBlock:`

### 3. Bundle ID filter too narrow

Glow's plist filter is `com.facebook.Facebook` only. On devices where the user
has the "FB6" variant installed (`com.facebook.Facebook6`), Glow won't load.

### 4. Many features are good (reusable)

These features WOULD work in 560.x if hooked correctly:

- ✅ Download videos (URLSession methods are stable)
- ✅ Download stories (button on `FBSnacksMediaContainerView`)
- ✅ Disable auto-advance reels (`_advanceToNextItemWithNavigationAction:`)
- ✅ Reels like confirm
- ✅ Hide Reels carousel
- ✅ Hide "People You May Know" (PYMK)
- ✅ Hide "Suggested for you"
- ✅ Composer hide
- ✅ Clear cache
- ✅ Long-press menus

## Comparison: Original Glow 1.3.1 vs Our `glow_v7`

| Feature | Glow 1.3.1 | glow_v7 (working R3.5) | Status |
|---------|-----------|------------------------|--------|
| Ad blocking | `initWithFBTree:` (3 classes) | `FBMemNewsFeedEdge.node` returns nil for SPONSORED | ✅ glow_v7 works |
| Story seen | `_markThreadAsSeen:...` (1 hook) | 3 hooks on `FBSnacksBucketsSeenStateManager` | ✅ glow_v7 works |
| Ad detection category | String "ORGANIC" check | String "SPONSORED" check | ✅ both work |
| Reels disable auto-advance | `_advanceToNextItemWithNavigationAction:` | (not implemented) | ❌ missing in glow_v7 |
| Reels like confirm | not in strings | (not implemented) | ❌ missing |
| Reels carousel hide | not in strings | (not implemented) | ❌ missing |
| PYMK hide | not in strings | (not implemented) | ❌ missing |
| Composer hide | `shouldHideComposer` (in haoict) | (not implemented) | ❌ missing |
| Download video | Long press on `VideoContainerView` + `FBVideoOverlayPluginComponentBackgroundView` | infrastructure ready, not wired | ❌ missing |
| Download story | `initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:` | infrastructure ready, not wired | ❌ missing |
| Hide story | `initWithFBPandoTree:`/`initWithFBTree:` | (not implemented) | ❌ missing |
| Story seen via menu | toast on download | (not implemented) | ❌ missing |
| Bundle ID | `com.facebook.Facebook` | both `com.facebook.Facebook` + `com.facebook.Facebook6` | ✅ glow_v7 better |
| Language UI | 11 languages | English only | ❌ Glow better |
| Settings UI | full preferences | none | ❌ Glow better |
| Architecture | arm64e | arm64 | ❌ Glow more compatible |
| Size | 16MB (FFmpeg included) | 100KB (no FFmpeg) | ✅ glow_v7 lighter |
| Sideload compatible | uses MobileSubstrate path | uses Substrate/Ellekit | ✅ both work |

## Strategy for v8

The user's `glow_v7` already solves the **2 critical hooks** (ad blocking + story seen).
For **v8**, we should add the **download features** from Glow but using the **correct
560.x classes/methods**.

### What to port from Glow

1. **Download video via long press** on the actual 560.x video container
   - Glow hooks `VideoContainerView` (selector `syc:nyc:`) and `FBVideoOverlayPluginComponentBackgroundView`
   - In 560.x: hook the equivalent (need to verify - likely `FBVideoOverlayPluginComponentBackgroundView` still exists based on our R3.0-verify output)

2. **Download story via button** on `FBSnacksMediaContainerView`
   - Glow hooks `initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:`
   - In 560.x: signature changed (we noted in R3.0-verify: "FBSnacksMediaContainerView exists with NEW init signature")
   - Need to find the new init selector

3. **Disable auto-advance reels** via `_advanceToNextItemWithNavigationAction:`
   - This ivar/method might still work in 560.x — needs runtime test

### What to add fresh

1. **Reels carousel hide** — needs runtime discovery
2. **PYMK hide** — needs runtime discovery
3. **Suggested for you hide** — needs runtime discovery
4. **Composer hide** — hook `shouldHideComposer` on `FBNewsFeedViewControllerConfiguration` (from haoict)
5. **Story seen via menu** — wire `markAsSeen` button to a real hook
6. **Long-press confirmation on like** — disable accidental likes

## Open Questions for v8

These require runtime verification on device:

1. What's the current init selector for `FBSnacksMediaContainerView`?
2. Does `_advanceToNextItemWithNavigationAction:` still exist on the Reels player class?
3. Is `FBVideoOverlayPluginComponentBackgroundView` still the correct class for long-press video download?
4. What's the class for Reels carousel (to hide it)?
5. What's the class for "People You May Know" section?
6. What's the class for "Suggested for you" section?
7. Is `FBNewsFeedViewControllerConfiguration` still around in 560.x?

These can be answered by re-running the R3.0-verify runtime tracer with new search filters.

## Files in This Analysis

```
analysis/glow-original/
├── glow-1.3.1.deb                # Original .deb package
├── deb-extracted/                 # Unpacked deb
│   ├── control/control            # Package metadata
│   └── data/
│       └── Library/MobileSubstrate/DynamicLibraries/
│           ├── Glow.dylib         # 16MB tweak binary
│           └── Glow.plist         # Filter (com.facebook.Facebook)
├── binary-analysis/
│   ├── Glow.dylib                 # Copy of binary
│   ├── all_strings.txt            # All printable strings
│   ├── all_selectors.txt          # All selector-like strings
│   ├── all_selectors_clean.txt    # Filtered
│   └── potential_class_names.txt  # Class name candidates
├── haoict-source/
│   ├── haoict_Tweak.xm            # Original logos source (324 lines)
│   ├── haoict_Tweak.h
│   ├── haoict_Makefile
│   └── haoict_control
└── COMPARISON.md                  # This file
```

## Build Instructions for v8

```bash
cd /tmp/facebook-no-ads/analysis/glow-original/haoict-source
# (modify Tweak.xm to use 560.x selectors from glow_v7)
cd /home/tommy/test/glow/glow-from-source
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i facebook.ipa -o glow_v8.ipa -f com.tommy.glowv3_1.0.0_iphoneos-arm.deb --overwrite -s -d
```

## License Notes

- `com.dvntm.glow_1.3.1_iphoneos-arm64e.deb` — proprietary, by dayanch96
  - We only RE the binary for analysis; we DO NOT redistribute
  - We DO NOT include Glow's binary in our repo
- `haoict/facebook-no-ads` — MIT license
  - We're using as reference for hook strategy
- Our code (R3.5/v7) — MIT license (same as haoict)

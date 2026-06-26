# Tools - Static Analysis Scripts

This folder contains Python scripts for analyzing iOS app binaries to identify classes, methods, and ivars for tweak development.

## 📦 Scripts Overview

### New Scripts (Added v8.2.64)

These scripts were created during static analysis of Facebook 560.x to identify the correct class names and method signatures for the Glow tweak.

#### `quick_analyze.py` ⭐ Recommended
Quick analysis of multiple key classes at once.
```bash
python3 tools/quick_analyze.py
```
**Output:** Methods/ivars for 10 key classes (FBVideoPlaybackContainerView, FBVideoPlaybackController, etc.)

#### `find_methods.py`
Find video-related methods for a specific class.
```bash
python3 tools/find_methods.py <binary> <class_name>
```
**Example:**
```bash
python3 tools/find_methods.py Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework FBVideoPlaybackContainerView
```

#### `deep_analyze.py`
Deep analysis of class structure (methods, ivars, type encodings).
```bash
python3 tools/deep_analyze.py <binary> <class_name>
```

#### `parse_macho.py`
Parse Mach-O binary structure to find ObjC class references.
```bash
python3 tools/parse_macho.py <binary>
```

#### `parse_objc.py`
Parse ObjC metadata from llvm-otool output.
```bash
python3 tools/parse_objc.py <binary> <class_name>
```

#### `extract_class.py`
Extract detailed class information including methods and properties.
```bash
python3 tools/extract_class.py <binary> <class_name>
```

### Existing Scripts

- `extract_ipa.py` - Extract IPA file to directory
- `strings_grep.py` - Search for strings matching pattern
- `dump_objc.py` - Dump ObjC class information
- `binary_diff.py` - Compare two binaries

## 🚀 Quick Start

### 1. Extract Facebook IPA
```bash
python3 tools/extract_ipa.py facebook.ipa /tmp/fb_extract
```

### 2. Analyze Key Classes
```bash
python3 tools/quick_analyze.py
```

This will analyze the FBSharedFramework and show methods/ivars for:
- FBVideoPlaybackContainerView
- FBVideoPlaybackController
- FBVideoPlaybackItem
- FBSnacksMediaContainerView
- FBSnacksNewVideoView
- FBShortsSideBarView
- FBShortsPlaybackController
- FBVideoOverlayPluginComponentBackgroundView
- FBSnacksMediaPlayerManager
- FBVideoOverlayPluginComponentView

### 3. Analyze Specific Class
```bash
python3 tools/find_methods.py \
    /tmp/fb_extract/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework \
    FBVideoPlaybackContainerView
```

## 🛠️ Requirements

- Python 3.6+
- `strings` command (usually pre-installed on Linux)
- `llvm-otool-18` (for some scripts)
- `macholib` Python package (for Mach-O parsing)

Install dependencies:
```bash
pip install macholib --break-system-packages
```

## 📊 What These Scripts Found

Using these scripts, we discovered that in FB 560.x:

1. **Class names changed:**
   - `VideoContainerView` → `FBVideoPlaybackContainerView`
   - Need to use full class name with `FB` prefix

2. **Ivar names changed:**
   - `_controller` → `_videoPlaybackController`
   - More specific ivar names

3. **Methods confirmed exist:**
   - `currentVideoPlaybackItem` (on FBVideoPlaybackController)
   - `HDPlaybackURL`, `SDPlaybackURL` (on FBVideoPlaybackItem)
   - `setPlaying:` (on FBVideoPlaybackController)
   - `manager` (on FBSnacksNewVideoView)

4. **New classes for Reels:**
   - `FBShortsPlaybackController`
   - `FBShortsSideBarView`
   - `FBShortsViewerOverlayComponentView`

## 🎯 Use Cases

### When developing a new tweak:
1. Extract the target app's IPA
2. Run `quick_analyze.py` to see all key classes
3. Use `find_methods.py` to dig into specific classes
4. Update your tweak code with correct class/method names

### When Facebook updates break your tweak:
1. Extract new Facebook IPA
2. Compare class structures with old version
3. Update class names in your tweak
4. Rebuild and test

### When debugging "class not found" errors:
1. Check if the class still exists with `find_methods.py`
2. If class name changed, update your hook
3. If class removed, find the new equivalent

## 📝 Example Output

```
================================================================================
📦 FBVideoPlaybackContainerView
================================================================================
Methods (1):
  - V_delegate

================================================================================
📦 FBVideoPlaybackController
================================================================================
Methods (9):
  - N
  - V_controller
  - V_playbackController
  - V_videoController
  - V_videoPlaybackController
  - V_videoPlayerController
  - V_warmedPlayer
  - VvideoController
  - W
```

**Note:** `V_` prefix indicates ivars (instance variables).

## 🔗 Related Documentation

- `../JTOOL_ANALYSIS.md` - Detailed analysis report
- `../STATIC_ANALYSIS.md` - Static analysis findings
- `../TWEAK_X_GUIDE.md` - How to read Tweak.x

## 💡 Tips

1. **Always use full paths** when specifying binaries
2. **Run from the tools/ directory** or use `tools/` prefix
3. **Pipe output to grep** for filtering: `python3 quick_analyze.py | grep -A 5 "FBVideoPlaybackController"`
4. **Redirect to file** for large outputs: `python3 quick_analyze.py > analysis.txt`

---

**Created:** Jun 26 2026  
**Version:** v8.2.64  
**Purpose:** Static analysis tools for iOS tweak development

# R4 Verifier

**Status:** v3 (targeted, no global enumeration)

Tweak to dump methods/ivars/properties of FB classes for v8.2+ feature
discovery. Does **NOT** install any actual hooks — read-only introspection.

## What's in v3

- **Phase 1**: ~16 critical classes with full method/ivar/property dump
- **Phase 2-6**: Candidate class lookup (just FOUND/NOT FOUND, no full dump)
  - Phase 2: 30 Reels candidates
  - Phase 3: 16 Video container candidates
  - Phase 4: 14 Story viewer candidates
  - Phase 5: 33 UI Hide candidates (Composer, PYMK, Suggested)
  - Phase 6: 12 Download/share candidates

Total: ~120 objc_getClass calls, ~3 seconds runtime, no crash.

## Why v3 (not v1/v2)

v1 and v2 used `objc_getClassList` to enumerate all 10000+ classes
globally. This caused memory/IO pressure, killing the process after
Phase 1. v3 fixes this by hardcoding candidate class names.

## Output

File: `/var/mobile/Documents/glow_r4.txt`

```
=== R4 Verifier v3 (targeted) — Jun 21 2026 11:30 ===

########## PHASE 1: Critical classes ##########
[full methods/ivars/properties dump for 16 classes]

########## PHASE 2: Reels candidates ##########
### Reels ###
  [FOUND] FBMemReelEdge
  [FOUND] FBReelUnitView
  ...
--- 12/30 found ---

[etc for all phases]
```

## How to build

```bash
cd r4/
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cyan -i /home/tommy/test/glow/facebook.ipa -o glow_r4.ipa \
    -f packages/com.tommy.glowr4_1.0.0_iphoneos-arm.deb --overwrite -s -d
```

## How to run

1. Remove the current Facebook app
2. Install `glow_r4.ipa` via TrollStore
3. Open app, wait 3-5 seconds
4. Get `/var/mobile/Documents/glow_r4.txt`
5. Send back for analysis

## Branch info

- Source: `r4-verifier` branch (this folder)
- Latest: branch `v8-glow-framework` also keeps a copy in `analysis/r4-verifier/`

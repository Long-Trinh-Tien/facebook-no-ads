# Glow Clone — Facebook iOS Ad Blocker

A working iOS tweak to:
- **Block ads** in Facebook news feed
- **Disable story seen** (view stories anonymously)
- Built for **Facebook 560.x** on **iOS 16+** with **TrollStore** (no jailbreak)

## Features

✅ **Ad blocking** — removes sponsored posts in news feed (no empty gaps)
✅ **Story seen disabled** — view stories without the creator knowing
❌ Download story (TODO)
❌ Download video (TODO)
❌ Hide Reels / People You May Know / Suggested (TODO)

## Status: WORKING (R3.5/v7)

```
=== Glow R3.5/v7 — <date> ===
[ctor] viewDidAppear hook installed
=== Installing hooks (R3.5/v7) ===
  hook #0: FBMemNewsFeedEdge.node -> nil for SPONSORED
  hook #1: cellForItem
  hook #2: willDisplay
  hook #3: _sendSeenThreadIDsWithBucket:session: -> no-op
  hook #4: _sendThreadIDsAsSeenInViewerSession: -> no-op
  hook #5: markThreadsView... -> no-op
=== Done ===
```

## Quick Start

```bash
# Build
cd /path/to/repo
THEOS=/home/tommy/theos make package FINALPACKAGE=1

# Inject into Facebook IPA
cyan -i /path/to/facebook.ipa \
     -o /path/to/glow_v7.ipa \
     -f ./packages/com.tommy.glowv3_1.0.0_iphoneos-arm.deb \
     --overwrite -s -d

# Install via TrollStore
# AirDrop glow_v7.ipa to device → Open in TrollStore → Install
```

## Documentation

- **[README.md](README.md)** — Overview
- **[AGENTS.md](AGENTS.md)** — Session context, investigation journey, key files
- **[INVESTIGATION_GUIDE.md](INVESTIGATION_GUIDE.md)** — Teaching guide: methods, tools, when to use
- **[BUILD_GUIDE.md](BUILD_GUIDE.md)** — Build & test instructions, troubleshooting
- **[UPDATE_GUIDE.md](UPDATE_GUIDE.md)** — 15-min workflow khi FB update version mới
- **[VERSION_COMPAT.md](VERSION_COMPAT.md)** — Compatibility matrix qua các FB versions

## How It Works

The original Glow tweak (for older FB versions) hooked `FBMemNewsFeedEdge.initWithFBTree:` to return nil for ads — preventing them from being created at the model layer.

In **FB 560.x**, `initWithFBTree:` is GONE. But the class still has 3 methods: `node`, `deduplicationKey`, `category`.

We hook **`FBMemNewsFeedEdge.node`** to return nil when `category == "SPONSORED"`. This is the closest analog to the old approach — at the model layer, before the layout is computed.

```
CKDataSourceItem
    └── _model: FBSectionComponentDataSourceModel
            └── _model: FBFeedFetchedEdge
                    └── _edge: FBMemNewsFeedEdge
                            ├── node (returns feed unit) ← WE HOOK THIS
                            ├── deduplicationKey
                            └── category (ORGANIC, SPONSORED, etc.)
```

When `node` returns nil, ComponentKit never computes a layout for that cell, so no space is allocated (no empty gaps).

## Architecture

6 hooks total:
- 1 on `FBMemNewsFeedEdge.node` — model layer filter (primary)
- 2 on `FBComponentCollectionViewDataSource` — cell hiding (backup)
- 3 on `FBSnacksBucketsSeenStateManager` — story seen (3 paths blocked)

All output to single log file: `/var/mobile/Documents/glow.txt`

## Verified

Tested on:
- Facebook 560.x
- iOS 16+ (TrollStore)
- Both `com.facebook.Facebook` and `com.facebook.Facebook6` bundle IDs

## Build Environment

- Theos (`/home/tommy/theos/`)
- iOS SDK 16.5+
- cyan for IPA injection
- TrollStore for installation

See [BUILD_GUIDE.md](BUILD_GUIDE.md) for details.

## License

Private project.

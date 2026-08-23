# SESSION HANDOVER — Glow v8.3.7-dbg

## Current State (Jun 28 2026)

### Build: 1.3.7-dbg (debug, logging-only)
- **`packages/glow_v8.ipa`** — IPA cuối (đã ghi đè)
- **`packages/com.tommy.glowv3_1.3.7-dbg_iphoneos-arm.deb`**

### Enabled modules (in Tweak.x):
| Module | Status | Note |
|--------|--------|------|
| AdBlockHooks | ✅ ON | `FBMemNewsFeedEdge.node` → nil cho SPONSORED |
| StorySeenHooks | ✅ ON | **ĐÃ SỬA:** gọi orig IMP, ko no-op 100% |
| StoryDownloadHooks | ✅ ON | **LOG-ONLY:** ko thêm button, ko download |

### Disabled modules (ALL others):
NewsfeedVideoHooks, ReelsDownloadHooks, PlaybackStateHooks, VideoItemHooks, LongPressHooks, RuntimeEnumHooks, ExplorerHooks

### Version banner: `Glow v8.3.7-dbg (DEBUG LOGGING BUILD — Story evidence)`

---

## Key Discoveries (this session)

### 1. Root Cause — Story crash FREEZE (not crash)

**Symptom:** "Story ấn vào đơ luôn" — tap story ring → app freezes  
**Wrong assumption (xuyên suốt v8.3.0→v8.3.6):** Nghĩ crash do StoryDownloadHooks  
**Evidence from log:** `[dbg/story] HOOKED init + didMoveToWindow` nhưng ko có `init called` → freeze xảy ra TRƯỚC khi init chạy

**Actual cause: StorySeenHooks no-op ko gọi original IMP**
- `_sendSeenThreadIDsWithBucket:session:` — no-op hoàn toàn
- `_sendThreadIDsAsSeenInViewerSession:` — no-op hoàn toàn
- FB cần các methods này chạy để update internal state → freeze vì ko có side effect

**Fix applied (v8.3.7-dbg):** Gọi `orig_seen*` trước khi log, vẫn ghi "blocked"

### 2. StorySeenHooks có thể block seen nhưng vẫn gọi orig
Cần gọi IMP gốc để duy trì internal state, nhưng vẫn ngăn seen receipt gửi lên server. Có thể hook tầng network thay vì tầng này.

### 3. RuntimeEnumHooks đúng là có bug
Lines 180-222 hook `setVideoPlayer:`, `setPlaybackController:`, `configureWithVideo:`, `configureWithModel:` trên ALL FB classes với 1 `orig_*` pointer duy nhất → sai IMP khi nhiều class tự implement method. **Cần verify lại sau khi fix freeze.**

### 4. Story từng hoạt động ở v8.2.64 (31e2fbf)
Code story download ở v8.2.64 là code chuẩn. Em đã inline y hệt vào v8.3.6.

---

## What's Pending

### Immediate — Verify Story download works
1. Fix freeze (đã làm) → deploy → test xem story có mở được ko
2. Kiểm tra log `[dbg/story] init called` + `didMoveToWindow` + URL walk
3. Nếu log ra URL → implement button thật
4. Nếu ko ra URL → sửa `findMediaURLInContainer:` path

### After story works
5. **Bật lại RuntimeEnumHooks** với fix (chỉ target FBVideoPlaybackController)
6. **Bật lại ReelsDownloadHooks** — cần log evidence rằng `FBShortsSideBarView` tồn tại
7. **Reels button trên Reel đầu tiên** — hiện chỉ xuất hiện từ Reel #2
8. **Newsfeed video download** — `FBVideoPlaybackContainerView` ko tìm thấy trong 560.x

### Critical Known Issues
- `RuntimeEnumHooks.xm:180-222` — hooks ALL FB classes với 1 orig IMP → sai (chưa bật)
- `noop_seen_3` function signature có thể sai type cho `isSeen:` (BOOL vs id) — method chưa được gọi nên chưa crash
- Settings Glow ko có UI entry point (LongPressHooks disabled)
- StorySeenHooks hiện gọi orig IMP → seen sẽ được gửi (cần network hook để block)

---

## Key Files to Read Next Session

| File | Why |
|------|-----|
| `Core/StoryDownloadHooks.xm` | LOG-ONLY version, cần restore thành real implementation |
| `Core/StorySeenHooks.xm` | Đã sửa để gọi orig IMP, cần cải thiện |
| `Core/RuntimeEnumHooks.xm` | Bug đã identified, chờ fix |
| `Tweak.x` | Control module activation |
| `Managers/GlowStoryHandler.m` | Có thể bỏ (đã inline vào StoryDownloadHooks) |

## Commands

```bash
cd ~/test/facebook-no-ads
THEOS=/home/tommy/theos make package FINALPACKAGE=1     # Build deb
cyan -i /home/tommy/test/glow/facebook.ipa -o packages/glow_v8.ipa -f packages/com.tommy.glowv3_*.deb --overwrite -s -d   # Build IPA
cp packages/glow_v8.ipa /home/tommy/test/glow/glow_v8.ipa
python3 Tests/test_managers.py                          # 49 unit tests
git add -A && git commit -m "..." && git push            # Commit + push
```

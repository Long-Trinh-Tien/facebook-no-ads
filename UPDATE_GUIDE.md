# Quick Update Guide — Khi Facebook Release Version Mới

> Hướng dẫn NHANH (15-30 phút) để cập nhật tweak khi Facebook update.
> Đọc file này TRƯỚC khi đụng vào code.

---

## Khi nào cần update?

Facebook update mỗi 1-2 tuần. Update có thể:
- Đổi tên class (vd: `FBMemNewsFeedEdge` → `FBXxxFeedEdge`)
- Đổi method signature (vd: `initWithFBTree:` → `initWithFBTree_v2:`)
- Đổi category string (vd: `SPONSORED` → `AD`)
- Xóa method/class (vd: `FBMemFeedStory` đã bị xóa)

Khi user báo "không hoạt động" → update ngay.

---

## 15-Minute Update Workflow

### Bước 1 (1 phút): Build verifier với binary mới

```bash
# Đặt FB binary mới vào đúng vị trí
cp /path/to/new/facebook.ipa /home/tommy/test/glow/facebook.ipa

# Build verifier (đã có sẵn source ở /home/tommy/test/glow/glow-verify/)
cd /home/tommy/test/glow/glow-verify
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cp packages/com.tommy.glowverify_1.0.0_iphoneos-arm.deb /home/tommy/test/glow/glowverify.deb

# Inject vào FB
cyan -i /home/tommy/test/glow/facebook.ipa \
     -o /home/tommy/test/glow/glow_verify_v2.ipa \
     -f /home/tommy/test/glow/glowverify.deb \
     --overwrite -s -d
```

### Bước 2 (3 phút): Install + collect log

1. Install `glow_verify_v2.ipa` qua TrollStore
2. Mở Facebook, login, đợi 10s
3. Dùng Files app: copy `/var/mobile/Documents/glow_verify.txt`
4. Đọc log

### Bước 3 (5 phút): Phân tích log

Mở log, tìm:

```bash
# Classes còn tồn tại
grep "FOUND" glow_verify.txt

# Classes bị xóa
grep "MISSING" glow_verify.txt

# Categories mới (nếu có)
grep "category" glow_verify.txt
```

**Check quan trọng:**
- ✅ `FBMemNewsFeedEdge` FOUND?
- ✅ `FBSnacksBucketsSeenStateManager` FOUND?
- ✅ `node` method còn?
- ✅ `_sendSeenThreadIDsWithBucket:session:` còn?
- ✅ Categories: `ORGANIC`, `SPONSORED` còn?

### Bước 4 (5 phút): Nếu có thay đổi

**Nếu class đổi tên** (vd: `FBMemNewsFeedEdge` → `FBXxxFeedEdge`):

```bash
# Search binary cho pattern tương tự
strings /path/to/FBSharedFramework | grep -iE "Feed.*Edge|NewsFeed.*Edge" | head -20
```

**Nếu method đổi tên:**
```bash
# Search selector cũ trong binary mới
strings /path/to/FBSharedFramework | grep "_sendSeen"
```

**Nếu category đổi:**
```bash
# Search cho "AD" "SPONSOR" "PROMOTE"
strings /path/to/FBSharedFramework | grep -iE "^(AD|SPONSOR|PROMOTE)" | head -20
```

### Bước 5 (3 phút): Update Tweak.x

Edit `/home/tommy/test/glow/glow-v3/Tweak.x`:

```objc
// Đổi class name
Class memEdgeCls = objc_getClass("FBMemNewsFeedEdge");  // → "FBNewName"

// Đổi method name
SEL nodeSel = sel_registerName("node");  // → "newMethodName"

// Đổi category check
if ([cs isEqualToString:@"SPONSORED"])  // → "NEW_CATEGORY"
```

### Bước 6 (2 phút): Rebuild + test

```bash
cd /home/tommy/test/glow/glow-v3
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cp packages/com.tommy.glowv3_1.0.0_iphoneos-arm.deb /home/tommy/test/glow/glowv7.deb
cyan -i /home/tommy/test/glow/facebook.ipa \
     -o /home/tommy/test/glow/glow_v7.ipa \
     -f /home/tommy/test/glow/glowv7.deb \
     --overwrite -s -d
```

Install, test, commit.

---

## 30-Minute Update Workflow (Khi Có Nhiều Thay Đổi)

Nếu nhiều classes/methods đổi, dùng workflow dài hơn:

### Bước 1: Build verifier (5 phút)
Như trên.

### Bước 2: Static analysis (10 phút)

```bash
# Get new FB binary
cd /tmp
mkdir -p fb-bin-new
unzip -o /path/to/new/facebook.ipa -d fb-bin-new/

# Search cho các classes quan trọng
strings fb-bin-new/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework | \
  grep -iE "^(FB.*Feed.*Edge|FeedUnit|Snacks.*Seen|SnacksMedia|Vid.*Overlay)" | head -40

# Search cho selectors
strings fb-bin-new/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework | \
  grep -iE "asFB.*Sponsor|_sendSeen|initWithFB" | head -20
```

### Bước 3: Diff với version cũ (5 phút)

```bash
# Save old symbols
strings ~/glow-snapshots/560.x/FBSharedFramework | sort > /tmp/old_syms.txt

# Save new symbols
strings /tmp/fb-bin-new/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework | sort > /tmp/new_syms.txt

# Diff
diff /tmp/old_syms.txt /tmp/new_syms.txt | head -50
```

### Bước 4: Update Tweak.x (5 phút)
Như workflow 15 phút.

### Bước 5: Test thoroughly (5 phút)
- Mở FB
- Scroll news feed
- Check story seen
- Verify ads hidden
- Check log

---

## Maintenance Schedule

| Frequency | Task | Time |
|-----------|------|------|
| **Weekly** | Check App Store cho FB update | 2 min |
| **On update** | Run 15-min update workflow | 15 min |
| **Monthly** | Review log, optimize code | 30 min |
| **Quarterly** | Review tool chain, update docs | 1 hour |
| **Yearly** | Major refactor, test new iOS | 4 hours |

---

## Maintain Snapshots

Lưu snapshot mỗi version FB để diff sau này:

```bash
# Save snapshot
mkdir -p ~/glow-snapshots/$(date +%Y-%m-%d)
cp /path/to/facebook.ipa ~/glow-snapshots/$(date +%Y-%m-%d)/
cp glow.txt ~/glow-snapshots/$(date +%Y-%m-%d)/
cp glow_verify.txt ~/glow-snapshots/$(date +%Y-%m-%d)/

# Diff with old
diff -q ~/glow-snapshots/2025-01-01/glow.txt \
        ~/glow-snapshots/2025-06-15/glow.txt
```

---

## Red Flags — Investigate Lại

Khi nào KHÔNG dùng 15-min workflow:

- ❌ **5+ classes MISSING** — FB refactor lớn
- ❌ **All categories đổi** — backend API thay đổi
- ❌ **50%+ items throw exception** — model layer thay đổi
- ❌ **Hook method exist nhưng never fires** — call site đã đổi
- ❌ **App crash ngay khi mở** — incompatible change

Trong những trường hợp này:
1. Đọc FB changelog (nếu public)
2. Search github cho similar projects
3. Fall back to deep investigation

---

## Emergency Recovery

Nếu update làm tăng app crash:

1. Revert to last known good:
   ```bash
   git log --oneline  # find last good commit
   git checkout <commit-hash> -- Tweak.x
   ```

2. Build với old code:
   ```bash
   THEOS=/home/tommy/theos make package FINALPACKAGE=1
   # Old code vẫn có thể work với new binary (silent degradation)
   ```

3. Test xem có work không — nếu có, OK chờ update tiếp

4. Nếu crash, uninstall tweak:
   ```bash
   # Dùng TrollStore để uninstall
   ```

---

## Version Tracking Template

Tạo file `VERSIONS.md` track:

```markdown
# Facebook Version Compatibility

| FB Version | Date | FBMemNewsFeedEdge | node method | Categories | Status | Notes |
|------------|------|-------------------|--------------|------------|--------|-------|
| 555.0.0 | 2025-01-XX | ✓ | ✓ | ORGANIC, SPONSORED | OK | First test |
| 560.1.0 | 2025-06-XX | ✓ (3 methods) | ✓ | ORGANIC, SPONSORED, ENGAGEMENT | OK | v7 working |
| 561.0.0 | - | ? | ? | ? | Unknown | Need test |
```

---

## Quick Reference — Search Commands

```bash
# Find classes
strings FBSharedFramework | grep -E "^FB.*(Feed|Edge|Snacks|Seen)"

# Find methods
strings FBSharedFramework | grep -E "^as[A-Z]|^_[A-Z]|^is[A-Z]"

# Find categories
strings FBSharedFramework | grep -E "^(ORGANIC|SPONSORED|ENGAGEMENT|AD)"

# Find C functions
nm FBSharedFramework 2>/dev/null | grep " T _FB"
```

---

## Kết luận

**Mục tiêu:** Mỗi lần FB update, tốn **tối đa 15-30 phút** để update tweak.

**KHÔNG BAO GIỜ** investigate từ đầu khi đã có:
- Verifier tool (đã build sẵn)
- Investigation guide (đã viết)
- Snapshot các version cũ
- Workflow rõ ràng

**Khi cần deep investigation:** chỉ khi 5+ classes đổi cùng lúc (major refactor) — hiếm.

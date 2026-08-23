# AGENTS.md — Glow for Facebook (Tweak iOS)

> File duy nhất chứa toàn bộ thông tin để **tái tạo môi trường**, **clone repo**, **build**, **deploy**, và **debug**.
> Viết để chuyển môi trường làm việc từ Linux x86_64 (laptop) sang **Raspberry Pi (Linux ARM64)**.

---

## 1. TỔNG QUAN DỰ ÁN

| Item | Giá trị |
|------|---------|
| Mục đích | Facebook ad blocker + downloader (Story/Video/Reels) cho FB 560.x |
| Tên tweak | GlowV3 (bundle `com.tommy.glowv3`) |
| Version hiện tại | **v8.4.1** (control: `1.4.1`) — git HEAD `73d4c9b` |
| Platform | iOS 16+ (TrollStore, **KHÔNG jailbreak**) |
| Facebook target | 560.x (`com.facebook.Facebook`, `com.facebook.Facebook6`) |
| Build system | Theos (Linux) |
| Injection | cyan (IPA injection) |
| Trạng thái | Ads block ✅ / Story seen ✅ / Story download ✅ / Reels download ✅ / Newsfeed video ✅ / Settings UI ✅ / Long-press settings tab bar ⚠️ (gesture lên quá nhiều views) |

---

## 2. GITHUB

- **Repo:** `https://github.com/Long-Trinh-Tien/facebook-no-ads`
- **Branch chính:** `v8-glow-framework`
- Các branch khác (tham khảo): `master`, `r4-verifier`, `analysis/glow-original`, `remotes/origin/qwen-glow`, `remotes/origin/analyze`
- **LƯU Ý BẢO MẬT:** git remote hiện có chứa token trong URL (`https://ghp_xxx@github.com/...`). Khi clone trên máy mới, **KHÔNG được ghi token vào AGENTS.md / file nào trong repo**. Nếu cần push, dùng SSH key riêng.
- `.gitignore`: `.theos/`, `packages/`, `analysis/` (glow_v8.ipa >100MB nên ko push lên GitHub)

```bash
git clone -b v8-glow-framework https://github.com/Long-Trinh-Tien/facebook-no-ads.git
cd facebook-no-ads
```

---

## 3. TÁI TẠO MÔI TRƯỜNG (Raspberry Pi — Linux ARM64)

### 3.1 Cấu trúc thư mục chuẩn (bắt buộc)

```
~/test/
├── glow/                    ← thư mục chứa facebook.ipa (đặt song song repo)
│   ├── facebook.ipa         ← IPA FB 560.x đã decrypt (BASE, khoảng 190MB)
│   └── glow_v8.ipa          ← thành phẩm cuối (copy từ packages/)
└── facebook-no-ads/         ← repo (clone từ GitHub)
    ├── Tweak.x              ← entry point
    ├── Makefile             ← build config
    ├── build.sh             ← build script chính
    ├── control              ← version + package metadata
    ├── Core/                ← hooks (Logos/runtime)
    ├── Managers/            ← business logic
    ├── UI/                  ← GlowSettingsViewController
    ├── Utils/               ← shared helpers
    ├── Logger/              ← 00GlowLogger (trace MSHookMessageEx)
    ├── tools/               ← Python static analysis
    ├── Tests/               ← 49 unit tests (chạy trên Linux)
    └── packages/            ← output (.deb + .ipa)
```

**Quan trọng:** `build.sh` tìm `facebook.ipa` tại `$REPO_PARENT_DIR/glow/facebook.ipa` (tức `~/test/glow/facebook.ipa` nếu repo ở `~/test/facebook-no-ads`).

### 3.2 Cài hệ thống packages

```bash
sudo apt update
sudo apt install -y \
    git make clang llvm python3 python3-pip \
    radare2 binutils libplist-utils libplist-dev libplist++-dev \
    cmake file bsdmainutils curl \
    dpkg-dev fakeroot
```

- `llvm` → cung cấp `llvm-otool-18` (otool trên máy này = `llvm-otool-18`)
- Python packages:
```bash
pip3 install --break-system-packages lief macholib capstone keystone-engine biplist
```

### 3.3 Cài Theos

```bash
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS
# hoặc nếu clone lỗi submodule:
# git clone https://github.com/theos/theos.git $THEOS && cd $THEOS && git submodule update --init --recursive
```

**SDK (bắt buộc):** Theos cần iOS SDK trong `$THEOS/sdks/`.
- Máy hiện tại có: `iPhoneOS12.4.sdk`, `iPhoneOS16.5.sdk`, `AppleTVOS12.4.sdk`
- **Dùng SDK 16.5** (phù hợp iOS 16+):
```bash
# Tải SDK: https://github.com/theos/sdks/releases
mkdir -p $THEOS/sdks
# Đặt iPhoneOS16.5.sdk vào $THEOS/sdks/
```

**LƯU Ý Raspberry Pi (ARM64):** Theos prebuilt toolchain trong `$THEOS/toolchain/linux/` là **x86_64** — KHÔNG chạy trên Pi. Cách xử lý trên Pi:
1. Kiểm tra Theos hỗ trợ `linux-arm64` toolchain: chạy script `$THEOS/bin/install-theos` hoặc cài clang cross:
```bash
sudo apt install -y clang lld
# Theos tự detect clang trong PATH khi toolchain không khớp arch
```
2. Verify build chạy được ngay sau khi clone (xem mục 5).

### 3.4 Cài cyan (IPA injection)

```bash
# Cần Go
sudo apt install -y golang-go
git clone https://github.com/aspect-build/cyan.git /tmp/cyan
cd /tmp/cyan && go build -o cyan .
sudo cp cyan /usr/local/bin/
# Verify
cyan --version   # cyan v1.4.4
```

Cyan flags dùng trong project: `-i <in> -o <out> -f <tweak.deb> --overwrite -u -w -e -d -s`
- `-u -w -e`: strip extensions/watchOS/extra
- `-s`: adhoc sign
- `-d`: debug mode (giữ documents support cho TrollStore)

### 3.5 File Facebook IPA

- Cần **IPA FB 560.x đã decrypt** (không thể tự làm nếu ko jailbreak — lấy từ trusted source)
- Đặt tại: `~/test/glow/facebook.ipa`
- File hiện có: `facebook.ipa` (~190MB)

### 3.6 Tạo thư mục output

```bash
mkdir -p ~/test/facebook-no-ads/packages
```

---

## 4. CẤU TRÚC CODE

```
Tweak.x                        ← %ctor → hook viewDidAppear → installHooks()
Core/Hooks.h                   ← extern "C" init function declarations
Core/AdBlockHooks.xm           ← hook #0 FBMemNewsFeedEdge.node → nil cho SPONSORED
Core/StorySeenHooks.xm         ← hook #3-5 block seen receipts (no-op)
Core/StoryDownloadHooks.xm     ← hook #8b FBSnacksMediaContainerView → long-press download
Core/NewsfeedVideoHooks.xm     ← hook #9b FBVideoPlaybackContainerView → long-press download
Core/VideoItemHooks.xm         ← hook #12a/b capture HDPlaybackURL/SDPlaybackURL
Core/ReelsDownloadHooks.xm     ← hook #11a/b/c FBShortsSideBarView → download button
Core/PlaybackStateHooks.xm     ← (disable — crash startup)
Core/LongPressHooks.xm         ← settings long-press: UITabBar hooks + proactive walk
Core/RuntimeEnumHooks.xm       ← (DISABLED — bug ở mục 7.2)
Core/ExplorerHooks.xm          ← stub
Managers/GlowLogManager.m      ← LOG macro → /var/mobile/Documents/glow.txt
Managers/GlowSettingsManager.m ← 19 settings keys (NSUserDefaults)
Managers/GlowCacheManager.m    ← URL caches, currentPlayingItem
Managers/GlowStoryHandler.m    ← story download logic
Managers/GlowVideoHandler.m    ← newsfeed video download
Managers/GlowReelHandler.m     ← reels button + overlay
UI/GlowSettingsViewController.m ← Settings modal (switch cells)
Utils/GlowViewUtils.m          ← keyWindow, topViewController, toast
Logger/Logger.xm               ← 00GlowLogger: hook MSHookMessageEx in-memory, trace logs
```

### Makefile tóm tắt

```makefile
ARCHS = arm64
TWEAK_NAME = GlowV3 00GlowLogger
GlowV3_FILES = Tweak.x + Core/*.xm + Managers/*.m + UI/GlowSettingsViewController.m + Utils/GlowViewUtils.m
GlowV3_FRAMEWORKS = UIKit Photos
GlowV3_CFLAGS = -fobjc-arc -Wno-error -I. -ICore -IManagers -IUI -IUtils
GlowV3_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
00GlowLogger_FILES = Logger/Logger.xm
```

Plist filter (`GlowV3.plist`): `com.facebook.Facebook`, `com.facebook.Facebook6`

---

## 5. BUILD

### Cách 1: build.sh (khuyến nghị)

```bash
cd ~/test/facebook-no-ads
./build.sh            # = check + deb + ipa
./build.sh deb        # chỉ build .deb
./build.sh ipa        # build deb + inject IPA
./build.sh clean      # xoá .theos/ + packages/*.deb (KHÔNG xoá ipa cũ)
./build.sh check      # kiểm tra môi trường (THEOS, cyan, facebook.ipa)
```

- `THEOS` mặc định: `/home/tommy/theos` (nếu ko set env, script tự set — **đổi lại trên Pi**)
- Output: `packages/com.tommy.glowv3_<version>_iphoneos-arm.deb` + `packages/glow_v8.ipa`

### Cách 2: thủ công

```bash
cd ~/test/facebook-no-ads
rm -rf .theos/
THEOS=~/theos make package FINALPACKAGE=1
# → packages/com.tommy.glowv3_1.4.1_iphoneos-arm.deb

cyan -i ~/test/glow/facebook.ipa \
     -o packages/glow_v8.ipa \
     -f packages/com.tommy.glowv3_1.4.1_iphoneos-arm.deb \
     -u -w -e -d -s --overwrite

cp packages/glow_v8.ipa ~/test/glow/glow_v8.ipa
```

### Troubleshooting build

| Lỗi | Fix |
|-----|-----|
| `missing iOS SDK` | `ls $THEOS/sdks/` → cần iPhoneOS16.5.sdk |
| `error: assigning to 'void (*)' from 'void *'` | IMP casts: dùng `typedef void (*Fn)(id,SEL,...); ((Fn)orig)(...)` (xem StorySeenHooks.xm) |
| `error: unknown type name 'BOOL'` | `#import <UIKit/UIKit.h>` hoặc `<objc/objc.h>` |
| `'Foundation' not found` | `-I$THEOS/include` đã có trong Makefile; kiểm tra SDK đúng arch |
| Build chậm | máy Pi ARM64 sẽ chậm hơn laptop x86_64 2-4x — chấp nhận hoặc chạy qua nuitka/docker x86 emulation |

---

## 6. TEST (chạy trên Linux, ko cần device)

```bash
cd ~/test/facebook-no-ads
python3 Tests/test_managers.py
# Ran 49 tests ... OK
```

Test cover: settings defaults, URL cache logic, filename patterns, v.v. (pure-Python mirror của logic ObjC).

---

## 7. DEPLOY + LOG (device)

### 7.1 Deploy

1. Copy `packages/glow_v8.ipa` → iPhone (AirDrop / usb / HTTP)
2. Mở bằng **TrollStore** → Install
3. Mở Facebook

### 7.2 Đọc log

| File | Nội dung |
|------|----------|
| `/var/mobile/Documents/glow.txt` | Log chính của GlowV3 |
| `/var/mobile/Documents/glow_sandbox.txt` | Log sandbox (00GlowLogger) |
| `/var/mobile/Library/Logs/CrashReporter/` | Crash reports (khi app sập) |

Lấy log từ device: dùng Files app / TrollStore file view, hoặc `idevicefileafc` (xem mục 11).

### 7.3 Banner chuẩn

```
=== Glow v8.4.1 (Modular Build) — <date> ===
[prefs] reload: ads=1 seen=1 video=1 story=1 pymk=1 reels=1
[ctor] viewDidAppear hook installed
=== Installing Glow v8.4.1 hooks ===
  hook #0: FBMemNewsFeedEdge.node -> nil for non-ORGANIC
  hook #3-5: seen no-op
  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add long press
  hook #9b: FBVideoPlaybackContainerView didMoveToWindow -> long press
  hook #12a/b: HDPlaybackURL/SDPlaybackURL capture
  hook: UITabBar.didMoveToWindow/layoutSubviews -> settings long press
[ui] added settings long press gesture to FBTabBarContainerView ...
[dl/reel] CAPTURED HD: https://scontent...mp4
[reels/main] ADDED button to overlay
=== Done ===
```

---

## 8. SETTINGS KEYS (NSUserDefaults `com.tommy.glow.*`)

| Key | Mặc định | Ý nghĩa |
|-----|---------|---------|
| `removeAds` | YES | Chặn ads |
| `disableStorySeen` | YES | Xem story ẩn danh |
| `downloadReels` | YES | Nút tải Reels |
| `downloadVideo` | YES | Tải video newsfeed |
| `downloadStory` | YES | Tải story |
| `removePYMK` | NO | Xóa People You May Know |
| `removeReelsCarousel` | NO | Xóa carousel Reels |
| `removeSuggested` | NO | Xóa Suggested |
| `hideComposer` | NO | Ẩn composer |
| `disableAutoNext` | NO | Tắt auto-next |
| `confirmLike` | NO | Xác nhận Like |
| `hideOverlay` | NO | Ẩn overlay |
| `confirmReelsLike` | NO | Xác nhận Like Reels |
| `downloadLongPress` | NO | Download bằng long-press (cũ) |
| `markAsSeen` | NO | Đánh dấu đã xem |
| `removeStoryPYMK` | NO | Xóa gợi ý kết bạn trong story |
| `allFormats` | NO | Tất cả format download |
| `clearCacheOnLaunch` | NO | Xóa cache khi mở |
| `notifyUpdates` | NO | Thông báo update |

Settings UI: long-press trên tab bar → GlowSettingsViewController modal (Tiếng Việt).

---

## 9. KEY CLASSES (FB 560.x)

| Class | Vai trò |
|-------|---------|
| `FBMemNewsFeedEdge` | `node` (→nil cho SPONSORED), `category` |
| `FBSnacksBucketsSeenStateManager` | seen receipts (3 methods) |
| `FBSnacksMediaContainerView` | Story container (didMoveToWindow → long press) |
| `FBVideoPlaybackContainerView` | Newsfeed video container (long press download) |
| `FBVideoPlaybackItem` | `HDPlaybackURL`/`SDPlaybackURL` capture |
| `FBShortsSideBarView` | Reels sidebar (download button overlay) |
| `UITabBar` / `FBTabBarContainerView` | Settings long-press target |

---

## 10. QUY TẮC VÀNG — KHÔNG CODE KHI CHƯA CÓ LOG EVIDENCE 🔴

Bài học từ 6 release crash (v8.3.0→v8.3.6): fix "đoán mò" vô ích.

**Trước khi implement feature MỚI:**
1. Build **LOG-ONLY** (chỉ log, KHÔNG replace IMP)
2. Install → device → mở feature cần test
3. Đọc `/var/mobile/Documents/glow.txt` → xác nhận class/method/timing tồn tại
4. **Chỉ khi đó** mới viết code thật

**Khi debug crash:**
1. KHÔNG đoán cause
2. Lấy crash log từ `/var/mobile/Library/Logs/CrashReporter/`
3. **Binary search**: disable từng module (1 module/build) cho đến khi crash biến mất
4. Đọc kỹ code module gây crash → fix

**Đã biết bug (v8.3.x era):**
- `RuntimeEnumHooks.xm:180-222`: hook `setVideoPlayer:`/`setPlaybackController:`/`configureWith*:` trên **ALL FB classes** với 1 `orig_*` IMP duy nhất → gọi sai IMP khi class khác tự implement → crash Story. **Fix:** chỉ hook class chứa `FBVideoPlaybackController` trong tên. Hiện module này đang **DISABLED**.
- `PlaybackStateHooks`: disable (gây crash startup).
- `noop_seen_3` signature có thể sai type BOOL vs id — method chưa được gọi nên chưa crash (cẩn thận khi enable).

**Quy tắc hook an toàn (ARM64):**
- `didMoveToWindow` KHÔNG nhận argument: signature hook phải là `(id self, SEL _cmd)` — nếu thêm `UIWindow *window` sẽ stack corruption
- `method_setImplementation` dễ crash ARC → ưu tiên Logos `%hook`/`%orig` nếu được
- Luôn `@try/@catch` quanh ivar walk

---

## 11. KẾT NỐI DEVICE (TrollStore + WSL2/Linux)

### Cách A: usbipd-win + libimobiledevice (USB)

```powershell
# Windows (Admin)
winget install usbipd
usbipd bind --busid <busid iPhone>
```

```bash
# WSL2/Linux
sudo apt install usbip libimobiledevice-utils ideviceinstaller
sudo usbip attach -r <Windows IP> -b <busid>
idevicesyslog | grep -i glow        # live log
ideviceinstaller -i glow_v8.ipa     # cài IPA
idevicefileafc ls /Documents        # xem file /var/mobile/Documents
```

### Cách B: Tailscale (ko cần USB)

Cài Tailscale cả iPhone + Pi → SSH/SFTP vào device qua tailnet IP.

### Cách C: mini HTTP server trong tweak (chưa làm — ý tưởng)

Thêm endpoint serve log + nhận lệnh qua IP cục bộ.

---

## 12. UPDATE WORKFLOW — KHI FACEBOOK RELEASE VERSION MỚI

1. Đặt FB binary mới → `~/test/glow/facebook.ipa`
2. Build verifier log-only → install → đọc log
3. Grep check: `FBMemNewsFeedEdge` FOUND? `node` còn? `_sendSeenThreadIDsWithBucket:session:` còn? categories còn `ORGANIC`/`SPONSORED`?
4. Class đổi tên → `python3 tools/find_methods.py <binary> <class>` tìm tên mới
5. Update code → build → test
6. Cập nhật `QUICK_REFERENCE.md` + version trong `control`

**Tools static analysis (trong repo):**
```bash
python3 tools/quick_analyze.py                                    # 10 key classes
python3 tools/find_methods.py Payload/.../FBSharedFramework FBVideoPlaybackContainerView
python3 tools/dump_objc.py <binary> <ClassName>
python3 tools/strings_grep.py <binary> Sponsor --type=class
python3 tools/extract_ipa.py facebook.ipa /tmp/fb_extract
```
Cần binary trích từ IPA: `Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework`

---

## 13. LỊCH SỬ VERSION (TÓM TẮT)

| Version | Nội dung |
|---------|----------|
| v7 / R3.5 | Ad block + story seen — WORKING baseline |
| v8.2.64 | Story download + Reels + newsfeed — **story hoạt động** |
| v8.2.68 | Modular refactor (Tweak.x 4294→100 dòng) |
| v8.3.0→8.3.6 | **Crash era** — fix sai target 6 lần (thủ phạm RuntimeEnumHooks) |
| v8.3.7 | Fix RuntimeEnumHooks (chỉ hook FBVideoPlaybackController) |
| v8.3.8 | Restore settings UI |
| v8.3.9 | Settings long-press → UITabBar hooks |
| v8.4.0 | Story seen fix, tab bar gesture, subclass video container |
| v8.4.1 | Revert story → long-press style, seen → void no-op |
| v8.4.2-3 | 00GlowLogger (trace MSHookMessageEx in-memory) |
| HEAD `73d4c9b` | **all functions are stable now** (trừ long-press tab bar icon chưa chuẩn) |

**Vấn đề đang mở (mục tiêu tiếp):**
- Long-press settings hiện add gesture lên QUÁ NHIỀU views (`FBTopBarAndContentView`, `FBStackView`, `UIDimmingView`...) — cần thu hẹp filter chỉ còn `FBTabBar*`/`TabBar` + chặn scan khi settings modal đang mở
- Reels button chỉ xuất hiện từ Reel #2 (race condition Reel #1)
- RuntimeEnumHooks còn disable

---

## 14. GHÉP NHỚ NHANH (cheat sheet)

```bash
# Build + deploy (mỗi lần đổi code):
cd ~/test/facebook-no-ads && ./build.sh
# → packages/glow_v8.ipa → TrollStore install → mở FB → đọc log

# Test nhanh (ko cần device):
python3 Tests/test_managers.py

# Version bump: sửa control (Version:) + banner trong Tweak.x (%ctor)

# Commit: git add -A && git commit -m "..." && git push origin v8-glow-framework
```

**Quy tắc bất biến:**
1. 🔴 NO CODE WITHOUT LOG EVIDENCE
2. KHÔNG `rm -rf packages/` — chỉ ghi đè file trong đó
3. `didMoveToWindow` signature = `(id self, SEL _cmd)` KHÔNG có arg window
4. Luôn bắt `@try/@catch` quanh ivar access
5. Settings mặc định `removeAds=YES`, `disableStorySeen=YES`, `downloadReels=YES`
6. Log file device: `/var/mobile/Documents/glow.txt`

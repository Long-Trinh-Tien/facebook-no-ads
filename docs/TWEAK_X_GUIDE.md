# 📖 Tweak.x - Hướng Dẫn Đọc Hiểu

**Mục đích:** Giúp bạn hiểu cấu trúc file Tweak.x (4294 dòng) một cách có hệ thống, từ tổng quan đến chi tiết.

**Đối tượng:** Người mới bắt đầu đọc code, hoặc cần refresh lại kiến thức sau thời gian nghỉ.

---

## 🎯 Tổng Quan Nhanh (30 giây)

**Tweak.x là gì?**
- File source chính của tweak "Glow for Facebook"
- Viết bằng Objective-C (không phải Swift, không phải Logos)
- Hook vào Facebook app để thêm/sửa tính năng
- Build bằng Theos → ra file `.deb` → inject vào Facebook.ipa

**Tweak làm gì?**
- ❌ Xóa quảng cáo
- 📥 Tải video/story/reels
- 👁️ Xem story ẩn danh
- 🎨 Ẩn composer, PYMK, suggested posts
- ⚙️ Settings UI bằng tiếng Việt

**Cấu trúc:** 7 SECTIONS theo thứ tự từ trên xuống dưới.

---

## 📂 Cấu Trúc File (7 Sections)

```
Tweak.x (4294 dòng)
├── SECTION 1: Settings storage           (dòng 43-103)   ← Lưu settings
├── SECTION 2: Settings UI                (dòng 105-479)  ← Giao diện settings
├── SECTION 3: Ad blocking                (dòng 480-714)  ← Xóa quảng cáo
├── SECTION 4: Story seen                 (dòng 715-740)  ← Xem ẩn danh
├── SECTION 4.5: v8.2 features           (dòng 741-3887) ← Tính năng mới
│   ├── Feature 1: Hide Composer
│   ├── Feature 2: Hide PYMK
│   ├── Feature 3: Download Story         ← FIX trong v8.2.64
│   ├── Feature 4: Download Video         ← FIX trong v8.2.64
│   │   ├── FIX 1: Newsfeed video
│   │   ├── FIX 2: Story button
│   │   └── FIX 3: Reels button
├── SECTION 5: Long press settings        (dòng 3888-3893)
├── SECTION 6: Install hooks              (dòng 3895-4250) ← Cài đặt hooks
└── SECTION 7: %ctor - init               (dòng 4251-4294) ← Khởi động
```

---

## 🔄 Luồng Khởi Động (Entry Point)

```
┌─────────────────────────────────────────┐
│ iOS loads Facebook.app                   │
└──────────────┬──────────────────────────┘
               ↓
┌─────────────────────────────────────────┐
│ glow_init() - %ctor (SECTION 7)         │
│ - Load settings từ NSUserDefaults       │
│ - Listen for settings changes           │
└──────────────┬──────────────────────────┘
               ↓
┌─────────────────────────────────────────┐
│ dispatch_async to main queue             │
│ - Hook UIViewController.viewDidAppear:  │
└──────────────┬──────────────────────────┘
               ↓ (khi NewsFeed VC xuất hiện lần đầu)
┌─────────────────────────────────────────┐
│ hooked_viewDidAppear() → installHooks() │
│ (SECTION 6)                             │
└──────────────┬──────────────────────────┘
               ↓
┌─────────────────────────────────────────┐
│ installHooks() - cài TẤT CẢ hooks      │
│ - Hook #0: FBMemNewsFeedEdge.node       │
│ - Hook #1-2: cellForItem, willDisplay   │
│ - Hook #3-5: Story seen (3 paths)       │
│ - Hook #8: FBSnacksMediaContainerView   │
│ - Hook #9: FBVideoOverlayPlugin         │
│ - Hook #9b/c: FBVideoPlaybackContainerView │
│ - Hook #11a/b: FBShortsSideBarView     │
│ - Hook #12a/b: HDPlaybackURL/SDPlaybackURL │
└─────────────────────────────────────────┘
```

**Tại sao defer?** Facebook chưa load hết classes khi app vừa mở. Phải đợi NewsFeed VC xuất hiện thì mới hook được (classes đã được load).

---

## 📚 Chi Tiết Từng Section

### **SECTION 1: Settings Storage** (dòng 43-103)

**Mục đích:** Lưu/truy xuất settings từ `NSUserDefaults`.

**Cấu trúc:**
```objc
// 18 biến static BOOL - mỗi biến = 1 setting
static BOOL s_removeAds = YES;
static BOOL s_disableStorySeen = YES;
static BOOL s_downloadVideo = NO;
// ... 16 biến khác

// Hàm load từ NSUserDefaults
static void reloadPrefs(void) {
    NSUserDefaults *d = [NSNSUserDefaults standardUserDefaults];
    s_removeAds = [d boolForKey:@"com.tommy.glow.removeAds"];
    // ... load 18 settings
}

// Callback khi settings thay đổi (từ Settings.app)
static void prefsChanged(...) {
    reloadPrefs();
}
```

**Key pattern:**
- Mỗi setting có prefix `com.tommy.glow.*` (tránh trùng với app khác)
- Default: `removeAds=YES`, `disableStorySeen=YES`, `downloadReels=YES`, các cái khác = NO
- Settings được share với Settings.app qua UserDefaults

---

### **SECTION 2: Settings UI** (dòng 105-479)

**Mục đích:** Hiển thị bảng settings khi user long-press vào tab bar.

**Cấu trúc:**
```objc
// 1. Localization (dòng 110-200)
//    - GlowLoc(key) → trả về tiếng Việt
//    - Dictionary chứa ~50 strings

// 2. Helper functions (dòng 200-300)
//    - Tạo cell, section, switch

// 3. SettingsViewController class (dòng 300-479)
//    - UITableView với 5 sections:
//      • TRANG CHỦ (Home)
//      • REELS
//      • STORIES
//      • TRÌNH TẢI VIDEO (Downloader)
//      • KHÁC (Other)
```

**Cách hoạt động:**
- User long-press vào bất kỳ view nào (SECTION 5)
- → Hiện SettingsViewController
- → User toggle switch
- → Lưu vào NSUserDefaults
- → `prefsChanged()` được gọi
- → Tất cả biến `s_*` được update
- → Hooks kiểm tra `s_*` trước khi chạy

---

### **SECTION 3: Ad Blocking** (dòng 480-714)

**Mục đích:** Xóa quảng cáo khỏi NewsFeed.

**3 hooks chính:**

#### Hook #0: `FBMemNewsFeedEdge.node` (dòng 484-490)
```objc
static id hooked_node(id self, SEL _cmd) {
    id orig = orig_node ? ((id(*)(id, SEL))orig_node)(self, _cmd) : nil;
    NSString *category = [orig category];
    // Nếu là quảng cáo → trả về nil (FB sẽ không hiển thị)
    if (category && ![category isEqualToString:@"ORGANIC"]) {
        return nil;
    }
    return orig;
}
```

**Logic:** Mỗi bài viết trong Feed là 1 `FBMemNewsFeedEdge` object. Method `node` trả về data để hiển thị. Nếu category ≠ "ORGANIC" (tức là quảng cáo) → trả về nil → FB skip.

#### Hook #1-2: `cellForItem` + `willDisplay` (dòng 616-714)
- **Hook 1:** `collectionView:cellForItemAtIndexPath:` - tạo cell
- **Hook 2:** `collectionView:willDisplayCell:forItemAtIndexPath:` - cell sắp hiển thị
- **Mục đích:** Backup - nếu Hook #0 miss, ẩn cell bằng cách set `cell.hidden = YES` và `cell.alpha = 0`

**Flow:**
```
FB tạo cell (cellForItem) → tạo xong
FB chuẩn bị hiển thị (willDisplay) → hook chạy
   → Check category
   → Nếu là quảng cáo: cell.hidden = YES, cell.alpha = 0
   → Cell vẫn "tồn tại" nhưng không nhìn thấy
```

---

### **SECTION 4: Story Seen** (dòng 715-740)

**Mục đích:** Xem story mà người khác không biết (không gửi "seen" receipt).

**3 hooks chặn 3 đường gửi "seen":**

```objc
// Đường 1: _sendSeenThreadIDsWithBucket:session:
static void noop_seen_1(id self, SEL _cmd, id a, id b) {
    // KHÔNG gọi orig → không gửi seen
}

// Đường 2: _sendThreadIDsAsSeenInViewerSession:
static void noop_seen_2(id self, SEL _cmd, id a) {
    // KHÔNG gọi orig
}

// Đường 3: markThreadsView
static void noop_seen_3(id self, SEL _cmd, id a, id b, id c, BOOL d, id e, id f) {
    // KHÔNG gọi orig
}
```

**Pattern:** Thay vì gọi `orig` (implementation gốc), hàm rỗng → FB nghĩ đã gửi nhưng thực tế không.

---

### **SECTION 4.5: v8.2 Features** (dòng 741-3887) ⭐

**Đây là phần PHỨC TẠP NHẤT.** Chứa 4 features chính:

#### **Feature 1: Hide Composer** (dòng 745-776)
- Hook: `FBNewsFeedViewController.viewDidLoad`
- Set: `_shouldHideComposer = YES`
- Kết quả: Ẩn khung "Bạn đang nghĩ gì?" ở đầu NewsFeed

#### **Feature 2: Hide PYMK** (dòng 777-781)
- Hook: Walk view tree, tìm "People You May Know" cell, ẩn đi
- **Vấn đề:** `FBMemPeopleYouMayKnowEdge` chỉ có 0 methods trong 560.x → chưa hoạt động

#### **Feature 3: Download Story** (dòng 782-1219) 🔧 FIXED v8.2.64

**Cấu trúc:**
```
@interface GlowStoryDownloadHandler : NSObject
@end
@implementation GlowStoryDownloadHandler
    // Helper: Tìm URL từ container
    - (NSURL *)findMediaURLInContainer:isVideo:
    
    // Handler: Long press (cũ - không hoạt động)
    - (void)onStoryLongPress:
    
    // Handler: Button tap (MỚI - FIX v8.2.64)
    - (void)onStoryDownloadTapped:
    
    // Download logic
    - (void)downloadURL:toFileName:
@end
```

**Hooks:**
- `hooked_storyContainer_init` - hook init của `FBSnacksMediaContainerView`
- `hooked_storyContainer_didMoveToWindow` - thêm button khi view vào window 🔧

**FIX v8.2.64 (dòng 1166-1210):**
```objc
// BEFORE (bug):
btn.frame = CGRectMake(window.frame.size.width - 60, ...);
// → window có thể nil → crash

// AFTER (fix):
UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
btn.frame = CGRectMake(keyWindow.frame.size.width - 60, ...);
// → Luôn có keyWindow → button hiển thị đúng
```

#### **Feature 4: Download Video** (dòng 1220-3887) 🔧 FIXED v8.2.64

**Phức tạp nhất** - có 3 sub-features:

##### **FIX 1: Newsfeed Video** (dòng 1714-1842)
```
@implementation GlowVideoDownloadHandler (VideoContainer)
    - (void)onVideoContainerLongPress:  ← Handler
@end
```

**Logic:**
1. Hook `FBVideoPlaybackContainerView.initWithFrame:` và `.layoutSubviews`
2. Thêm long press gesture
3. Khi long press:
   - Tìm controller qua: `controller` property → `_controller` ivar → `_videoPlaybackController` ivar → responder chain
   - Lấy `currentVideoPlaybackItem`
   - Lấy `HDPlaybackURL` và `SDPlaybackURL`
   - Hiện action sheet

**FIX v8.2.64 (dòng 1719-1750):**
```objc
// BEFORE: tìm "VideoContainerView" (không tồn tại trong 560.x)
// AFTER: tìm "FBVideoPlaybackContainerView" (đúng class)
const char *candidates[] = {
    "FBVideoPlaybackContainerView",  // ← Ưu tiên
    "VideoContainerView",            // ← Fallback
    // ...
};
```

##### **FIX 2: Story Button** (đã giải thích ở trên)

##### **FIX 3: Reels Button** (dòng 3544-3887)

**Cấu trúc:**
```
@interface GlowReelButtonHandler : NSObject
@end
@implementation GlowReelButtonHandler
    - (void)onReelButtonTap:           ← Handler khi tap button
    - (void)downloadReelVideoFromView: ← Tìm URL
@end
```

**Hooks:**
- `hooked_shortsSideBarDidMoveToWindow` - thêm button khi sidebar vào window 🔧
- `hooked_shortsSideBarLayoutSubviews` - fallback

**FIX v8.2.64 (dòng 3544-3620):**
```objc
// BEFORE: thêm button trong layoutSubviews (sau khi layout xong → delay)
// AFTER: thêm button trong didMoveToWindow (cùng lúc với other buttons)
```

**Runtime Enum Hooks (dòng 2402-2550):**
```objc
void installGlowStyleReelsHook(void) {
    // 1. objc_getClassList - lấy TẤT CẢ classes
    // 2. Loop qua từng class
    // 3. Nếu class có method "setVideoItem:" → hook
    // 4. Nếu class có method "currentVideoPlaybackItem" → hook
    // 5. ... các methods khác
    
    // FIX v8.2.64: Chỉ hook setPlaying: trên FBVideoPlaybackController
    if (strstr(name, "FBVideoPlaybackController") != NULL) {
        // → hook
    }
}
```

**FIX v8.2.64 (dòng 2516-2531):**
```objc
// BEFORE: hook setPlaying: trên MỌI class respond (sai)
// AFTER: chỉ hook trên FBVideoPlaybackController
```

---

### **SECTION 5: Long Press Settings** (dòng 3888-3893)

**Mục đích:** Detect long press ở bất kỳ đâu → mở Settings.

**Hook:** `UIApplication.sendAction:to:from:forEvent:` (dòng 2569-2641)

**Logic:**
```objc
static BOOL hooked_sendAction_to_from_forEvent_(...) {
    if (sender is UIButton && target là view) {
        // Phân tích target class
        // Nếu là Facebook internal class → log
        // Detect long press gesture
    }
    return orig(...);  // Vẫn gọi orig
}
```

---

### **SECTION 6: Install Hooks** (dòng 3895-4250)

**Mục đích:** Entry point để cài TẤT CẢ hooks.

**Hàm chính:** `installHooks()` (dòng 3901)

**Flow:**
```objc
static void installHooks(void) {
    if (setupDone) return;  // Chỉ chạy 1 lần
    setupDone = 1;
    
    // 1. Install send action hook
    installSendActionHook();
    
    // 2. Hook FBMemNewsFeedEdge.node (ad blocking)
    if (s_removeAds) { ... }
    
    // 3. Hook cellForItem + willDisplay
    if (s_removeAds) { ... }
    
    // 4. Hook Story seen (3 paths)
    if (s_disableStorySeen) { ... }
    
    // 5. Hook NewsFeed viewDidLoad (hide composer)
    if (s_hideComposer) { ... }
    
    // 6. Hook Story container (download story)
    if (s_downloadStory) { ... }
    
    // 7. Hook Video overlay (legacy)
    if (s_downloadVideo) { ... }
    
    // 8. Hook VideoContainerView (newsfeed)
    if (s_downloadVideo) { ... }
    
    // 9. Hook Shorts sidebar (reels)
    if (s_downloadReels) { ... }
    
    // 10. Hook VideoPlaybackItem URLs
    if (s_downloadVideo) { ... }
    
    // 11. Hook UIViewController.viewDidAppear: (lazy)
    if (!viewDidAppearHooked) { ... }
}
```

**Quan trọng:** Hàm này được gọi từ `hooked_viewDidAppear` (SECTION 7).

---

### **SECTION 7: %ctor - Init** (dòng 4251-4294)

**Mục đích:** Khởi động tweak khi app load.

```objc
__attribute__((constructor))
static void glow_init(void) {
    // 1. Setup log path
    // 2. Load settings
    // 3. Listen for settings changes
    // 4. Defer hook installation
    dispatch_async(dispatch_get_main_queue(), ^{
        // Hook viewDidAppear
        // → Khi NewsFeed xuất hiện → installHooks()
    });
}
```

**`__attribute__((constructor))`** = chạy NGAY khi dylib load (trước khi app khởi động xong).

---

## 🎨 Pattern Quan Trọng

### **Pattern 1: Hook một method**

```objc
// Bước 1: Lưu implementation gốc
static IMP orig_xxx = NULL;

// Bước 2: Viết hàm thay thế
static void hooked_xxx(id self, SEL _cmd, /* params */) {
    // Gọi implementation gốc (nếu muốn)
    if (orig_xxx) {
        typedef void (*FnType)(id, SEL, /* params */);
        FnType fn = (FnType)(uintptr_t)orig_xxx;
        fn(self, _cmd, /* params */);
    }
    
    // Làm gì đó thêm
    LOG("hooked_xxx called\n");
    
    // Hoặc thay đổi return value
    // return something;
}

// Bước 3: Trong installHooks():
Class cls = objc_getClass("SomeClass");
if (cls) {
    Method m = class_getInstanceMethod(cls, @selector(someMethod));
    if (m) {
        orig_xxx = method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_xxx);
    }
}
```

### **Pattern 2: Kiểm tra setting trước khi chạy**

```objc
static void hooked_xxx(id self, SEL _cmd) {
    if (!s_someFeature) return;  // ← Quan trọng!
    // ... code
}
```

### **Pattern 3: Walk view hierarchy**

```objc
UIView *v = someView;
while (v) {
    if ([v isKindOfClass:[TargetClass class]]) {
        // Found!
        break;
    }
    v = v.superview;  // Hoặc v.nextResponder
}
```

### **Pattern 4: Associated Objects (gắn data vào view)**

```objc
// Set
objc_setAssociatedObject(view, "key", value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

// Get
id value = objc_getAssociatedObject(view, "key");

// Check đã set chưa
NSNumber *already = objc_getAssociatedObject(view, "GlowTag");
if (already) return;  // Đã làm rồi
```

### **Pattern 5: Safe performSelector**

```objc
// Thay vì gọi trực tiếp [self methodWithUnknownSelector]
// Dùng performSelector
SEL sel = sel_registerName("methodWithUnknownSelector");
if ([obj respondsToSelector:sel]) {
    id result = [obj performSelector:sel];
}
```

---

## 🔍 Cách Đọc Code Hiệu Quả

### **Bước 1: Đọc SECTION 7 (%ctor) trước**
Hiểu entry point → biết tweak bắt đầu từ đâu.

### **Bước 2: Đọc SECTION 6 (installHooks)**
Biết tweak hook những gì, theo thứ tự nào.

### **Bước 3: Đọc SECTION 1-2 (Settings)**
Hiểu cách user tương tác với tweak.

### **Bước 4: Đọc từng feature (SECTION 3, 4, 4.5)**
Đi sâu vào từng tính năng cụ thể.

### **Bước 5: Đọc comment "FIX v8.2.X"**
Các comment này giải thích TẠI SAO code viết như vậy, lịch sử thay đổi.

---

## 🐛 Debug Tips

### **1. Xem log trên device:**
```bash
# File log
/var/mobile/Documents/glow.txt

# Xem real-time
tail -f /var/mobile/Documents/glow.txt
```

### **2. Tìm log quan trọng:**
```bash
grep "\[dl/reel\]" glow.txt  # Reels logs
grep "\[dl/news\]" glow.txt  # Newsfeed logs
grep "\[dl/story\]" glow.txt # Story logs
grep "error\|exc\|crash" glow.txt  # Errors
```

### **3. Test trên device:**
- Install qua TrollStore
- Mở app
- Test từng tính năng
- Đọc log
- Nếu crash → grep "exc" trong log

### **4. Runtime verification:**
Nếu không biết class có tồn tại không, thêm log:
```objc
Class cls = objc_getClass("SomeClass");
if (cls) {
    LOG("✓ SomeClass EXISTS\n");
} else {
    LOG("✗ SomeClass NOT FOUND\n");
}
```

---

## 📊 Bản Đồ Tư Duy (Mental Map)

```
Tweak.x
│
├─ Khởi động
│  └─ %ctor (SECTION 7)
│     └─ viewDidAppear hook
│        └─ installHooks (SECTION 6)
│
├─ Settings
│  ├─ Storage (SECTION 1) ← 18 biến BOOL
│  └─ UI (SECTION 2) ← TableView tiếng Việt
│
├─ Ad Blocking (SECTION 3)
│  ├─ FBMemNewsFeedEdge.node → nil
│  └─ cellForItem + willDisplay → hide
│
├─ Story Seen (SECTION 4)
│  └─ 3 paths bị chặn
│
└─ v8.2 Features (SECTION 4.5)
   ├─ Hide Composer
   ├─ Hide PYMK
   ├─ Download Story 🔧
   │  └─ FBSnacksMediaContainerView → button
   ├─ Download Video 🔧
   │  ├─ Newsfeed: FBVideoPlaybackContainerView
   │  ├─ Reels: FBShortsSideBarView
   │  └─ Runtime enum: FBVideoPlaybackController
   └─ Long press settings (SECTION 5)
```

---

## 🎓 Tóm Tắt Bằng Một Câu

> **Tweak.x là 1 file Objective-C 4294 dòng, chia thành 7 sections: load settings → mở settings UI → chặn quảng cáo → chặn story seen → thêm 4 features mới (composer/StoryPYMK/Download Story/Download Video) → cài hooks → khởi động từ %ctor.**

---

## 📚 Tài Liệu Tham Khảo

- `STATIC_ANALYSIS.md` - Phân tích tĩnh FB binary
- `BUILD_GUIDE.md` - Cách build tweak
- `INVESTIGATION_GUIDE.md` - Lịch sử điều tra
- `COMPACT_SESSION.md` - Tóm tắt phiên làm việc
- `V8_STATUS.md` - Trạng thái phiên bản v8
- `V8.2.64_SUMMARY.md` - Tóm tắt v8.2.64 (version hiện tại)

---

**Tác giả:** Tự viết sau khi đọc xong 4294 dòng  
**Ngày:** Jun 26 2026  
**Version:** v8.2.64

# 📔 Glow Tweak — Cẩm Nang Reverse Engineering & Phát triển Tweak (Facebook iOS)

Tài liệu này tổng hợp toàn bộ kiến thức, bài học xương máu (thành công & thất bại), các cấu trúc kỹ thuật và template chuẩn hóa đã được tích lũy qua các chu kỳ phát triển tweak **Glow V3** trên ứng dụng **Facebook (phiên bản 560.x)** chạy iOS 16 (TrollStore/Cyan/Theos).

---

## 📌 PHẦN 1: BÀI HỌC XƯƠNG MÁU & NGUYÊN TẮC VÀNG

### 🔴 Quy Tắc Vàng: KHÔNG CÓ BẰNG CHỨNG LOG, KHÔNG ĐƯỢC VIẾT CODE
Thất bại lớn nhất trong chuỗi phiên bản từ `v8.3.0` đến `v8.3.6` (khiến Story bị crash/freeze liên tục) là do **phỏng đoán nguyên nhân**.
- **Sai lầm:** Khi Story bị crash, nhóm phát triển đoán lỗi do `StoryDownloadHooks` (nút/gesture tải Story) nên đã chỉnh sửa liên tục 6 lần mà không kiểm tra log crash thực tế. Thậm chí khi tắt hoàn toàn `StoryDownloadHooks` ứng dụng vẫn crash, nhưng lập trình viên vẫn bỏ qua manh mối này và tiếp tục "sửa" nó.
- **Sự thật:** Lỗi nằm ở `RuntimeEnumHooks` do việc hook tất cả class có tiền tố `"FB"` nhưng chỉ lưu 1 con trỏ `orig_*` duy nhất, gây sập bộ nhớ (`EXC_BAD_ACCESS`) khi các class khác nhau gọi trùng tên hàm.
- **Nguyên tắc:** 
  1. Luôn triển khai bản build **DEBUG chỉ ghi nhận Log** trước khi viết logic thực thi.
  2. Bất kỳ nghi vấn lỗi/crash nào cũng phải được định vị bằng cách **cô lập từng Module (Binary Search)** để tìm ra đúng file thủ phạm.
  3. Sử dụng Post-mortem Logs làm Stack Trace để khoanh vùng dòng code gây sập.

---

## 📌 PHẦN 2: BẢNG LỊCH SỬ CRASH & GIẢI PHÁP CHI TIẾT (CRASH HISTORY)

Dưới đây là bảng tổng hợp tất cả các lỗi crash nghiêm trọng đã gặp trong lịch sử dự án, nguyên nhân gốc rễ và cách khắc phục:

| Giai đoạn | Triệu chứng / Nguyên nhân | Giải pháp | Trạng thái |
| :--- | :--- | :--- | :---: |
| **R0** | Hook `addSubview:` trên iOS 16+ gây lặp vô hạn hoặc crash do xung đột vẽ UI. | Loại bỏ hook này vĩnh viễn, sử dụng các hook vòng đời controller thay thế. | ✅ Đã sửa |
| **R0** | Gọi `objc_copyClassList` ngay trong `%ctor` (constructor) khiến app sập khi vừa mở (do class list chưa load xong). | Trì hoãn việc gọi hoặc loại bỏ hoàn toàn việc copy class list lúc khởi động. | ✅ Đã sửa |
| **R0** | Đăng ký nhận thông báo `UIApplicationDidFinishLaunchingNotification` bị sai lệch timing. | Sử dụng `dispatch_after` hoặc đợi giao diện gốc khởi tạo xong mới đăng ký. | ✅ Đã sửa |
| **R1** | Quá trình quét Timer chạy liên tục ngay cả khi người dùng chưa đăng nhập. | Loại bỏ bộ quét Timer khi đăng nhập, trì hoãn cho đến khi vào màn hình chính. | ✅ Đã sửa |
| **R1** | Gọi `dlopen` và thực hiện duyệt class trong `setupAllHooks` gây đứng hình app (freeze). | Loại bỏ việc nạp thư viện động cưỡng bức lúc khởi chạy. | ✅ Đã sửa |
| **R1** | Gọi `object_getIvar` trên một ivar không phải là đối tượng ObjC (ví dụ: C++ struct) gây sập bộ nhớ. | Thực hiện kiểm tra kiểu dữ liệu (Type-check/Encoding) của ivar trước khi truy cập. | ✅ Đã sửa |
| **R1** | Quét responder chain quá sâu vào `FBNewsFeedViewController` lúc khởi tạo gây lặp vòng. | Loại bỏ việc duyệt sâu không cần thiết khi view chưa sẵn sàng. | ✅ Đã sửa |
| **R2** | Gọi `objc_getClassList` trên 5000+ classes gây lag/crash bộ nhớ. | Thêm bộ lọc tiền tố `"FB"` để thu hẹp phạm vi quét class của Facebook. | ✅ Đã sửa |
| **R2** | Bộ lọc tin quảng cáo so sánh kiểu dữ liệu mong đợi `FBFeedUnit` nhưng thực tế nhận được `CKDataSourceItem`. | Chuyển đổi cơ chế chặn quảng cáo xuống tầng Model (`FBMemNewsFeedEdge.node`). | ✅ Đã sửa |
| **R3.1** | Chặn quảng cáo quá tay làm ẩn luôn cả các bài đăng thông thường (organic posts). | Thêm bộ lọc kiểm tra category của bài viết chặt chẽ hơn. | ✅ Đã sửa |
| **R3.2-3.4**| Xuất hiện khoảng trống (layout gaps) trên bảng tin do Facebook đã tính toán layout trước khi ẩn view. | Không ẩn view ở tầng UI nữa, mà hook thẳng vào `node` của Edge để trả về `nil` (Facebook tự loại bỏ sạch khoảng trống). | ✅ Đã sửa |
| **v8.3.0** | `RuntimeEnumHooks` hook toàn bộ class chứa hàm video nhưng dùng chung 1 con trỏ `orig_*` -> sập bộ nhớ khi mở Story. | Loại bỏ hoàn toàn RuntimeEnumHooks. Chỉ hook trực tiếp vào class cụ thể như `FBVideoPlaybackController`. | ✅ Đã sửa |
| **v8.4.1** | Lệch thanh ghi ARM64 khi swizzle `didMoveToWindow` do truyền thêm tham số ảo `window` (hàm gốc không có đối số). | Sửa lại chữ ký hàm chuẩn `(id self, SEL _cmd)` và lấy window động qua `self.window`. | ✅ Đã sửa |
| **v8.4.1** | Nhấn giữ copy văn bản trên Bảng tin vẫn hiện Settings do khớp tương đối từ khóa `"BottomBar"`. | Đổi sang so sánh chuỗi tuyệt đối (`strcmp`) cho `"FBTabBar"` và `"FBTabBarItemDefaultView"`, loại trừ `"Feed"`, `"Cell"`, `"Card"`. | ✅ Đã sửa |
| **v8.4.1** | Biểu tượng Tab Bar icon nuốt cử chỉ nhấn giữ của tweak. | Tích hợp delegate `shouldBeRequiredToFailByGestureRecognizer` và `cancelsTouchesInView = YES` để override cử chỉ gốc. | ✅ Đã sửa |

---

## 📌 PHẦN 3: CÁC CASE STUDY ĐIỂN HÌNH & KỸ THUẬT KHẮC PHỤC

### 1. Tràn/Lệch Thanh Ghi trên ARM64 (Signature Mismatches)
* **Triệu chứng:** Người dùng mở trình xem ảnh (Photo Viewer) hoặc chuyển trang thì ứng dụng sập (crash) ngay lập tức.
* **Nguyên nhân:** Hook phương thức `didMoveToWindow` của UIView nhưng khai báo sai chữ ký hàm:
  `static void hooked_didMoveToWindow(id self, SEL _cmd, UIWindow *window)`
  Trong UIKit, `didMoveToWindow` trả về `void` và **không có tham số đầu vào**. Trên kiến trúc ARM64, việc truyền thêm tham số ảo `UIWindow *window` vào hàm hook sẽ làm lệch ngăn xếp/thanh ghi, gây hỏng bộ nhớ ngay khi view chuyển trạng thái.
* **Giải pháp:** Khai báo chính xác chữ ký hàm gốc và truy xuất window động qua getter:
  `static void hooked_didMoveToWindow(id self, SEL _cmd)` và lấy window bằng `[(UIView *)self window]`.

### 2. Trùng lặp/Nuốt Cử Chỉ (Gesture Recognizer Swallowing)
* **Triệu chứng:** Cử chỉ nhấn giữ (Long Press) để mở Settings đã được gán vào thanh Tab Bar nhưng khi người dùng nhấn giữ vào các icon (ví dụ: Notification) thì không hoạt động, hoặc hoạt động song song với menu gốc của Facebook.
* **Nguyên nhân:** 
  - Các icon của Facebook (`FBTabBarItemDefaultView`) sở hữu các cử chỉ tap/long-press gốc của chúng. iOS sẽ ưu tiên cử chỉ gốc và "nuốt" cử chỉ của tweak.
  - Khi gán gesture lên cả View cha (`FBTabBar`) và View con (`FBTabBarItemDefaultView`), sự kiện nhấn giữ sẽ kích hoạt ở cả hai lớp, dẫn đến Settings Menu bị hiện lên 2 lần (double presentation).
* **Giải pháp:**
  - Sử dụng `UIGestureRecognizerDelegate` để cho phép nhận diện song song và thiết lập quyền ưu tiên tuyệt đối (Precedence Override) thông qua phương thức `shouldBeRequiredToFailByGestureRecognizer`.
  - Sử dụng cờ Debounce/Presentation Guard để giới hạn tần suất mở Settings tối đa 1 lần mỗi giây.

### 3. Nhận Diện View Giao Diện Lấy Lệch Mục Tiêu (Container vs Target View)
* **Triệu chứng:** Tweak hoạt động nhưng người dùng long-press bất kỳ vị trí nào trên Bảng tin (Newsfeed) để sao chép văn bản thì menu Settings vẫn nhảy ra.
* **Nguyên nhân:**
  - Sử dụng tìm kiếm chuỗi tương đối (`strstr`) trên tên class view (như `"BottomBar"`, `"TabBar"`).
  - Vô tình khớp trúng các view lớn toàn màn hình (`FBTabBarAndContentView`, `FBTabBarContainerView`) hoặc các thanh Like/Comment/Share dưới mỗi bài viết bảng tin (`FBFeedAttachmentBottomBar`).
* **Giải pháp:**
  - Dùng so sánh chuỗi tuyệt đối (`strcmp`) để khóa cứng mục tiêu vào đúng class chứa icon (`FBTabBar`, `FBTabBarItemDefaultView`).
  - Thiết lập bộ lọc loại trừ (Exclusion list) để bỏ qua ngay lập tức bất kỳ class nào chứa các từ khóa `"Feed"`, `"Component"`, `"Cell"`, `"Card"`.

---

## 📌 PHẦN 4: CÁC CODE TEMPLATE CHUẨN HOÁ

Dưới đây là các khuôn mẫu code (Templates) chuẩn hóa dùng để phát triển các tính năng và xử lý lỗi trên iOS:

### Template 1: Ghi Log Ra File `/var/mobile/Documents/glow.txt`
```objc
#import <Foundation/Foundation.h>

static char g_log_path[256] = {0};

static void initLogPath(void) {
    const char *home = getenv("HOME");
    if (home) {
        snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow.txt", home);
    }
}

static void LOG(const char *format, ...) {
    if (g_log_path[0] == 0) {
        initLogPath();
    }
    va_list args;
    va_start(args, format);
    
    // In ra NSLog (để xem qua Console)
    va_list args_copy;
    va_copy(args_copy, args);
    NSLogv([NSString stringWithUTF8String:format], args_copy);
    va_end(args_copy);
    
    // Ghi vào file Documents/glow.txt
    FILE *f = fopen(g_log_path, "a");
    if (f) {
        vfprintf(f, format, args);
        fclose(f);
    }
    va_end(args);
}
```

### Template 2: Hook UIView.didMoveToWindow Chuẩn ARM64 (Không đối số)
```objc
static IMP orig_view_didMoveToWindow = NULL;

static void hooked_view_didMoveToWindow(id self, SEL _cmd) {
    // 1. Gọi hàm gốc
    if (orig_view_didMoveToWindow) {
        typedef void (*Fn)(id, SEL);
        ((Fn)orig_view_didMoveToWindow)(self, _cmd);
    }
    
    // 2. Kiểm tra an toàn class để tránh ảnh hưởng đến các UIView khác
    if (![self isKindOfClass:objc_getClass("FBVideoPlaybackContainerView")]) return;
    
    // 3. Lấy window một cách an toàn
    UIView *view = (UIView *)self;
    UIWindow *window = view.window;
    if (!window) return;
    
    // Thực thi logic của tweak tại đây...
}
```

### Template 3: Thiết Lập Cử Chỉ Đè Lên Cử Chỉ Gốc (Precedence Override)
```objc
@interface GlowGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation GlowGestureHandler

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        // Thực thi logic...
    }
}

// Cho phép hoạt động song song với cử chỉ mặc định của Facebook
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer 
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

// ÉP cử chỉ của Facebook phải chờ cử chỉ của chúng ta thất bại (Tweak sẽ ghi đè cử chỉ gốc)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer 
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end
```

### Template 4: Quét Chủ Động View Hierarchy Tìm TabBar (Proactive Walk)
```objc
static const void *kGlowSettingsLPKey = &kGlowSettingsLPKey;
static GlowGestureHandler *g_gestureHandler = nil;

static void tryAddGestureToTabBar(UIView *v) {
    if (!v || ![v isUserInteractionEnabled]) return;
    
    const char *className = class_getName(object_getClass(v));
    
    // Loại trừ các thành phần Bảng tin tránh ảnh hưởng copy-paste
    if (className && (
        strstr(className, "Feed") != NULL ||
        strstr(className, "Component") != NULL ||
        strstr(className, "Cell") != NULL
    )) {
        return;
    }
    
    // Khớp tuyệt đối đúng thanh TabBar và các nút biểu tượng Icon
    BOOL isTarget = (className && (
        strcmp(className, "FBTabBar") == 0 ||
        strcmp(className, "FBTabBarItemDefaultView") == 0
    ));
    
    if (!isTarget) return;
    
    // Tránh add trùng lặp gesture
    NSNumber *already = objc_getAssociatedObject(v, kGlowSettingsLPKey);
    if (already && [already boolValue]) return;
    
    if (!g_gestureHandler) {
        g_gestureHandler = [[GlowGestureHandler alloc] init];
    }
    
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:g_gestureHandler action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.8;
    lp.cancelsTouchesInView = YES; // Hủy các chạm của view gốc khi long-press thành công
    lp.delegate = g_gestureHandler;
    [v addGestureRecognizer:lp];
    
    objc_setAssociatedObject(v, kGlowSettingsLPKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void walkViewsRecursive(UIView *v, int depth) {
    if (!v || depth > 8) return;
    tryAddGestureToTabBar(v);
    for (UIView *sub in v.subviews) {
        walkViewsRecursive(sub, depth + 1);
    }
}

void installLongPressOnCurrentUI(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        if (@available(iOS 13.0, *)) {
            for (id scene in [app connectedScenes]) {
                if ([scene isKindOfClass:objc_getClass("UIWindowScene")]) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        walkViewsRecursive(w, 0);
                    }
                }
            }
        }
    });
}
```

---

## 📌 PHẦN 5: PROMPT DÀNH CHO AI AGENT Ở PHIÊN BẢN SAU

*Hãy copy và dán toàn bộ đoạn Prompt dưới đây vào ngữ cảnh của AI Agent mới khi Facebook có bản cập nhật mới hoặc khi cần bảo trì Tweak:*

```markdown
Bạn là một AI Agent chuyên nghiệp về Reverse Engineering iOS và phát triển tweak bằng Theos/Logos. Bạn đang tiếp quản dự án "Glow" (Tweak chặn quảng cáo, download Reels/Story/Video và xem ẩn danh trên ứng dụng Facebook iOS phiên bản 560.x+).

Hãy đọc kỹ các chỉ dẫn dưới đây để đảm bảo KHÔNG làm hỏng tweak và KHÔNG làm sập (crash) ứng dụng:

### 1. QUY TẮC "BẰNG CHỨNG LOG TRƯỚC TIÊN" (CRITICAL)
- Tuyệt đối KHÔNG viết code logic chức năng hoặc cố sửa lỗi crash dựa trên phỏng đoán.
- Khi có lỗi hoặc có bản cập nhật Facebook mới, hãy viết một bản build DEBUG chỉ có LOG (in ra tên class, phương thức và giá trị biến) để deploy lên thiết bị.
- Đọc file `/var/mobile/Documents/glow.txt` để lấy bằng chứng về sự tồn tại của class/method và cấu trúc của chúng trước khi bắt tay vào sửa code.

### 2. PHÒNG TRÁNH LỖI CRASH HÀM didMoveToWindow (ARM64)
- Khi hook hoặc swizzle phương thức `didMoveToWindow` của bất kỳ UIView nào, bắt buộc phải sử dụng chữ ký hàm KHÔNG CÓ THAM SỐ:
  `static void hooked_didMoveToWindow(id self, SEL _cmd)`
- Tuyệt đối không khai báo tham số thứ 3 `(UIWindow *window)` vì phương thức này của UIKit không có đối số. Việc khai báo sai sẽ gây lệch thanh ghi trên ARM64 và làm sập ứng dụng khi mở hình ảnh hoặc chuyển view. Lấy window qua `[(UIView *)self window]`.

### 3. TRÁNH HOOK ĐẠI TRÀ (RUNTIME ENUMERATION)
- Không sử dụng các đoạn mã quét toàn bộ danh sách class của ứng dụng (objc_copyClassList) để hook hàng loạt phương thức video/seen. Điều này gây crash lập tức khi mở Story.
- Chỉ hook trực tiếp vào các class đích đã được định vị rõ ràng (như `FBVideoPlaybackController`, `FBTabBar`, `FBSnacksMediaContainerView`).

### 4. GẮN CỬ CHỈ CHO TAB BAR & OVERRIDE CỬ CHỈ GỐC
- Thanh Tab Bar của Facebook 560.x là một thực thể tùy biến tên là `FBTabBar`, các nút icon bên trong là `FBTabBarItemDefaultView`.
- Không sử dụng tìm kiếm chuỗi tương đối chứa từ "TabBar" hoặc "BottomBar" vì sẽ bị dính vào các view container toàn màn hình (`FBTabBarAndContentView`) hoặc thanh Like/Comment dưới mỗi bài viết bảng tin. Hãy dùng so sánh chuỗi tuyệt đối `strcmp` đối với `"FBTabBar"` và `"FBTabBarItemDefaultView"`.
- Để đè lên các cử chỉ mặc định của Facebook (ví dụ: nhấn giữ icon Notification không bị hiện menu gốc của Facebook), bắt buộc phải gán `delegate` cho UILongPressGestureRecognizer và triển khai các hàm delegate cho phép đồng bộ song song cùng quyền ưu tiên:
  ```objc
  - (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(id)o { return YES; }
  - (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(id)o { return YES; }
  ```
- Sử dụng cờ bảo vệ (Debounce Guard) 1.0 giây tại hàm `openGlowSettings` để tránh việc mở đúp giao diện Cài đặt khi cả view cha và view con cùng bắt trúng cử chỉ.

### 5. CẤU TRÚC THƯ MỤC DỰ ÁN
- `Tweak.x`: File khởi tạo constructor chính và quản lý hook khởi đầu.
- `Core/`: Chứa file hook của từng tính năng riêng biệt (AdBlockHooks.xm, StorySeenHooks.xm, LongPressHooks.xm, ReelsDownloadHooks.xm, NewsfeedVideoHooks.xm).
- `UI/`: Chứa file giao diện cài đặt (GlowSettingsViewController).
- `Managers/`: Trình quản lý logic tải và xử lý video/story (GlowReelHandler, GlowStoryHandler).
- `Makefile`: Cấu hình biên dịch của Theos.
```

---

## 📌 PHẦN 6: KỸ THUẬT DYNAMIC INTERCEPTION (FAKE SUBSTRATE) ĐỂ GIẢI MÃ & CLONE TWEAK GỐC KHÔNG CRASH

Khi muốn phân tích và dịch ngược phiên bản tweak gốc của Glow (`com.dvntm.glow_1.3.1_iphoneos-arm64e.deb`), nhà phát triển thường đối mặt với hai trở ngại lớn:
1. **String Encryption (Mã hóa chuỗi):** Toàn bộ tên class và selector đích đều bị mã hóa động trong phân đoạn dữ liệu tĩnh, ngăn cản việc phân tích tĩnh thông qua `strings` hoặc Radare2/Hopper.
2. **Crashes do đổi phiên bản Facebook:** Khi cài tweak gốc v1.3.1 lên các bản Facebook mới (như 560.x), tweak sẽ cố gắng hook các class không còn tồn tại -> `MSHookMessageEx` nhận tham số `Class = nil` và gây crash ứng dụng ngay khi khởi chạy.

### 💡 Giải pháp: Đóng thế Substrate (Fake Substrate Interceptor)
Tweak của chúng ta đi kèm một mô-đun đặc biệt tại thư mục `Logger/` chứa `Logger.xm` (Fake CydiaSubstrate) và script `inject_logger.sh`.

#### Cơ chế hoạt động:
- Biên dịch `Logger.xm` thành một dylib giả lập tên là `CydiaSubstrate`.
- Đổi tên thư viện Substrate thật thành `CydiaSubstrateReal` và đóng gói cả hai cùng với `Glow.dylib` gốc vào IPA của Facebook.
- Khi ứng dụng chạy:
  1. `Glow.dylib` gốc sẽ tải thư viện `CydiaSubstrate` giả lập của ta.
  2. Bất kỳ khi nào tweak gốc gọi `MSHookMessageEx` hay `MSHookFunction`, hàm giả lập của ta sẽ bắt giữ (intercept), giải mã và ghi lại tên Class, Selector, địa chỉ hàm thay thế ra file log `/var/mobile/Documents/glow_logger.txt`.
  3. **Đặc biệt (Crash Prevention):** Nếu class cần hook bị `nil` (do Facebook bản mới đã xóa bỏ class đó), Fake Substrate sẽ **bỏ qua không chuyển tiếp cuộc gọi hook đó sang Substrate thật**, giúp ngăn chặn 100% tình trạng sập ứng dụng.
  4. Nếu class tồn tại hợp lệ, Fake Substrate sẽ nạp động `CydiaSubstrateReal` để đăng ký hook thật sự.

### 🛠️ Hướng dẫn tiêm tự động và lấy log:
Chúng ta đã viết sẵn script tự động hóa toàn bộ quy trình trên tại [Logger/inject_logger.sh](file:///home/tommy/test/facebook-no-ads/Logger/inject_logger.sh).

**Cách chạy lệnh:**
```bash
./Logger/inject_logger.sh
```

**Chi tiết các bước script thực hiện:**
1. Kiểm tra môi trường (yêu cầu file deb gốc tại `/home/tommy/test/glow/com.dvntm.glow_1.3.1_iphoneos-arm64e.deb` và file IPA gốc tại `../glow/facebook.ipa`).
2. Giải nén file deb gốc để trích xuất `Glow.dylib` của nhà phát triển gốc.
3. Biên dịch `Logger.xm` thành dylib giả lập `CydiaSubstrate` trỏ link `@rpath/CydiaSubstrate.framework/CydiaSubstrate`.
4. Copy dylib Substrate thật của Theos đặt tên thành `CydiaSubstrateReal`.
5. Đóng gói cả hai thành các gói deb tạm thời rồi chạy `cyan` để tiêm song song vào Facebook IPA, xuất ra thành phẩm tại: `packages/glow_original_logged.ipa`.

**Cách lấy dữ liệu:**
1. Tải file `packages/glow_original_logged.ipa` lên điện thoại và cài đặt qua TrollStore.
2. Mở ứng dụng Facebook và lướt qua một số màn hình (Reels, Story, Newsfeed) để kích hoạt các hook của tweak gốc.
3. Mở file log tại điện thoại:
   👉 `/var/mobile/Documents/glow_logger.txt`
4. Toàn bộ danh sách các class, selector và symbol mà tweak gốc đã hook sẽ hiển thị chính xác 100%. Từ đây bạn có thể dễ dàng clone lại logic của họ mà không tốn công dịch ngược nhị phân mã hóa!

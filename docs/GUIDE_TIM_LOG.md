# 🔍 Hướng Dẫn Chiến Lược Chẩn Đoán "Không Đoán Mò" Trên iOS

Khi viết tweak hoặc nghịch đảo (reverse-engineer) các ứng dụng lớn như Facebook, việc **phỏng đoán** cấu trúc lớp/giao diện thường dẫn tới crash hoặc lỗi lệch pha dữ liệu. 

Dưới đây là cẩm nang hướng dẫn phương pháp **"Không Đoán Mò"** bằng cách dựng dump runtime giao diện và bộ nhớ, lấy ví dụ thực tế từ Reels download.

---

## 🛠️ Công cụ 1: Quét Đệ Quy Toàn Bộ Giao Diện (`dumpSubviewsRecursive`)
Khi bạn tìm thấy một view tổng (ví dụ: `FBVideoPlaybackContainerView`) nhưng không biết các thành phần con của nó là gì, hãy viết hàm quét đệ quy để in ra sơ đồ cây subviews:

```objc
static void dumpSubviewsRecursive(UIView *parent, int depth) {
    if (!parent || depth > 10) return;
    for (UIView *sub in parent.subviews) {
        // In ra thụt lề theo độ sâu (depth), tên Class, frame, hidden và alpha
        LOG("[diag/ui] %*s- %s (%p) frame=(%.1f, %.1f, %.1f, %.1f) hidden=%d alpha=%.2f\n", 
            depth * 2, "", 
            object_getClassName(sub), sub, 
            sub.frame.origin.x, sub.frame.origin.y, sub.frame.size.width, sub.frame.size.height, 
            sub.hidden, sub.alpha);
        
        // Quét tiếp các con của subview này
        dumpSubviewsRecursive(sub, depth + 1);
    }
}
```

---

## 💾 Công cụ 2: In Toàn Bộ Biến Nội Bộ (`class_copyIvarList`)
Đôi khi các bộ điều khiển (Controller) hoặc dữ liệu (URLs, Models) được lưu trong các biến nội bộ (ivars) không có property/getter công khai. Chúng ta sử dụng Runtime Objective-C để "chụp ảnh" toàn bộ ivars:

```objc
#import <objc/runtime.h>

static void dumpIvarsOfView(UIView *view) {
    if (!view) return;
    
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(view), &ivarCount);
    LOG("[diag/mem] === IVARS DUMP FOR %s (%p) ===\n", object_getClassName(view), view);
    
    for (unsigned int i = 0; i < ivarCount; i++) {
        Ivar ivar = ivars[i];
        const char *ivarName = ivar_getName(ivar);
        const char *ivarType = ivar_getTypeEncoding(ivar);
        ptrdiff_t offset = ivar_getOffset(ivar);
        
        // Nếu ivar là kiểu đối tượng (bắt đầu bằng dấu @)
        id val = nil;
        if (ivarType[0] == '@') {
            // Đọc an toàn giá trị ivar bằng con trỏ offset tránh ARC retain crash
            val = object_getIvar(view, ivar);
        }
        
        LOG("[diag/mem]   - %s (Type: %s) -> Value: %s (%p)\n",
            ivarName, ivarType, 
            val ? object_getClassName(val) : "nil", val);
    }
    
    if (ivars) free(ivars);
}
```

---

## ⛓️ Công cụ 3: Quét Ngược Chuỗi Phản Hồi (`Responder Chain Walk`)
Nếu muốn tìm xem ViewController nào đang quản lý view hiện tại, ta có thể đi ngược lên `nextResponder` của UIKit cho tới khi chạm tới đích:

```objc
static UIViewController *findViewControllerFromView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        responder = [responder nextResponder];
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}
```

---

## 📖 Case Study Thực Tế: Sửa Lỗi Lệch Pha Reels Download

### 1. Hiện tượng lỗi
Nút tải Reels hiển thị trên màn hình nhưng khi nhấn thì luôn tải lệch sang video tiếp theo hoặc báo "video not found". 

### 2. Dùng log chẩn đoán
Khi người dùng nhấn nút tải, ta lấy View ở tâm màn hình là `FBVideoPlaybackContainerView` và chạy hàm `dumpIvarsOfView`:

```
[reels/diag] DIAGNOSTIC DUMP for FBVideoPlaybackContainerView (0x15d6330d0):
[reels/diag] Ivars list (20):
  - _downloader (type: @"<FBImageDownloading>", offset: 384) -> value: MOSImageDownloader (0x15884ea00)
  ...
  - _currentLayer (type: @"CALayer", offset: 456) -> value: FNFIOSurfacePlayerLayer (0x15d634760)
  - _delegate (type: @"<FBVideoPlaybackContainerViewDelegate>", offset: 480) -> value: FBVideoPlaybackController (0x15d532420)
```

### 3. Phát hiện & Sửa đổi
* **Phát hiện:** Biến nội bộ `_delegate` trỏ thẳng tới `FBVideoPlaybackController` hiện tại đang phát trên màn hình!
* **Giải pháp sửa đổi chính xác:**
  ```objc
  id controller = nil;
  Ivar ivar = class_getInstanceVariable(object_getClass(container), "_delegate");
  if (ivar) {
      controller = object_getIvar(container, ivar);
  }
  ```
  Nhờ lấy đúng controller từ `_delegate`, tweak truy vấn được `currentVideoPlaybackItem` chuẩn xác và tải đúng video đang hiển thị.

---

## 🔴 Nguyên Tắc Gỡ Lỗi Sự Cố (Post-Mortem Debugging)
Khi ứng dụng bị sập (Crash) đột ngột mà không có Xcode Debugger:
1. Đặt các dòng log chi tiết với nhãn rõ ràng (ví dụ: `[adblock] bước 1`, `[adblock] bước 2`) ngay trước và sau mỗi câu lệnh nhạy cảm.
2. Ép ghi dữ liệu ghi đè ngay lập tức ra file `/var/mobile/Documents/glow.txt` bằng cách mở và đóng file ngay lập tức (`fopen` / `fprintf` / `fclose`).
3. Dòng log cuối cùng xuất hiện trong file chính là ranh giới gây sập. Bạn sẽ biết câu lệnh nào bị lỗi mà không cần phỏng đoán.

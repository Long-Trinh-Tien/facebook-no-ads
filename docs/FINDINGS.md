# 🔍 Glow Tweak Analysis & Findings — v1.3.1 original deb

Tài liệu này ghi nhận kết quả dịch ngược tĩnh (Static Reverse Engineering) trên file deb gốc: `/home/tommy/test/glow/com.dvntm.glow_1.3.1_iphoneos-arm64e.deb`.

---

## 📁 1. Cấu trúc thư mục của original deb
```
extracted_glow
├── Library
│   ├── Application Support
│   │   └── Glow.bundle (Assets.car, Info.plist, base & 9 lproj localizations)
│   └── MobileSubstrate
│       └── DynamicLibraries
│           ├── Glow.dylib (17 MB Mach-O 64-bit arm64 dynamically linked library)
│           └── Glow.plist (Nhắm mục tiêu com.facebook.Facebook và com.facebook.Facebook6)
```

---

## ⚙️ 2. Tại sao `Glow.dylib` lại nặng tới 17MB?
Từ danh sách symbols và class references, chúng ta phát hiện `Glow.dylib` liên kết tĩnh (statically link) với các thư viện sau:
1. **FFmpegKit / FFMpegHelper / FFmpegExecution**: Để gộp luồng hình ảnh HD (video-only) và âm thanh HD (audio-only) của luồng DASH do Facebook phân tách trên thiết bị thành 1 file MP4 hoàn chỉnh.
2. **MPDParser**: Để parse file MPEG-DASH Manifest (.mpd) mô tả các phân đoạn stream video.
3. **Swift Standard Library**: Tweak chứa code Swift hoặc liên kết tĩnh runtime.

---

## 🏛️ 3. Danh sách các Class tùy biến (Custom Classes) trong `Glow.dylib`
Được trích xuất từ bảng ký hiệu `__objc_classlist` và `__objc_classrefs`:

| Class Name | Vai trò / Mô tả |
|------------|-----------------|
| `GlowUserDefaults` | Quản lý lưu trữ cấu hình chuyển đổi (Tương tự `GlowSettingsManager` của ta) |
| `SettingsViewController` | Giao diện cài đặt của Glow |
| `WelcomeVC` | Màn hình giới thiệu / Onboarding khi chạy lần đầu |
| `ChangelogVC` | Hiển thị lịch sử thay đổi phiên bản |
| `ToastManager`, `ToastView`, `ToastWindow` | Quản lý thông báo dạng popup (Toast) như "Đang tải...", "Đã lưu..." |
| `Downloader`, `DownloaderHelper` | Trình quản lý tải xuống file và tích hợp tiến trình |
| `DVNLongPressGestureRecognizer` | Cử chỉ nhấn giữ tùy chỉnh |
| `DVNSheetController`, `DVNSheetPresenter`, `PseudoDetentController` | Giao diện Bottom Sheet tùy biến để chọn chất lượng tải (HD / SD) |

---

## 🔒 4. Phát hiện về Obfuscation (Ẩn mã) của `Glow.dylib`
Khi phân tích hàm constructor tại địa chỉ `0x80e0` bằng `radare2` (r2), chúng ta đã phát hiện:
1. **Control Flow Obfuscation (Ẩn luồng thực thi):**
   - Tweak sử dụng các lệnh nhảy gián tiếp qua thanh ghi (`br x8` tại `0x8280`).
   - Đích đến của cú nhảy (`x8`) được tính toán động bằng các phép XOR và âm hóa toán hạng tại runtime (ví dụ dùng key `0xace5` và `0x8ce2` tại địa chỉ `0x8148-0x814c`).
   - Điều này giải thích tại sao `r2` không thể phân tích tĩnh các cuộc gọi XREFs đến `MSHookMessageEx` và `objc_getClass` một cách bình thường.
2. **String Encryption (Mã hóa chuỗi):**
   - Các tên class và selector của Facebook (như `FBSnacksMediaContainerView`, `markThreadsViewReceipts...`) đều được mã hóa trong phân đoạn dữ liệu tĩnh và chỉ được giải mã động lên stack khi cần thiết. Do đó, chạy lệnh `strings` thông thường không thể tìm thấy các chuỗi này.

---

## 🧪 5. Kế hoạch hành động: Sandwich Hooking
Vì tĩnh bị Obfuscate mạnh, phương án tối ưu nhất là **Dynamic Interception (Sandwich Hooking)**:
1. Tạo một tweak logger tên `00GlowLogger.dylib` (có thứ tự load trước `Glow.dylib`).
2. Tweak này sẽ hook các hàm runtime của Objective-C/C:
   - `MSHookMessageEx`
   - `method_setImplementation`
   - `class_replaceMethod`
3. Khi `Glow.dylib` gốc chạy và giải mã chuỗi thành công để đăng ký hook, tweak logger của chúng ta sẽ chụp lại tên Class, Selector, địa chỉ hàm thay thế và ghi toàn bộ danh sách ra file `/var/mobile/Documents/glow_logger.txt` trên thiết bị.
4. Từ file log này, chúng ta sẽ có danh sách **chính xác 100% các hook của Glow gốc** để re-write vào source code của mình.

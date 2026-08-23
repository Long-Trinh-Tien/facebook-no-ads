#!/bin/bash
# Logger/inject_logger.sh - Tự động hóa quá trình xây dựng Tweak Logger và tiêm song song cùng Glow gốc vào Facebook IPA.
# Phiên bản này sử dụng cơ chế Hook Substrate trực tiếp trong bộ nhớ (In-Memory Interception), đảm bảo không gây crash ứng dụng.

set -e

# Màu sắc thông báo
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Đường dẫn tĩnh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
ORIG_DEB="/home/tommy/test/glow/com.dvntm.glow_1.3.1_iphoneos-arm64e.deb"
ORIG_IPA="$REPO_DIR/../glow/facebook.ipa"
OUTPUT_DIR="$SCRIPT_DIR/build_temp"
FINAL_IPA="$REPO_DIR/packages/glow_original_logged.ipa"

echo -e "${BLUE}=== BẮT ĐẦU QUÁ TRÌNH TIÊM LOG CHO TWEAK GLOW GỐC (IN-MEMORY HOOK) ===${NC}"

# 1. Kiểm tra môi trường
if [ ! -f "$ORIG_DEB" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy file deb gốc tại: $ORIG_DEB${NC}"
    exit 1
fi

if [ ! -f "$ORIG_IPA" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy file Facebook IPA gốc tại: $ORIG_IPA${NC}"
    exit 1
fi

if [ -z "$THEOS" ]; then
    THEOS="/home/tommy/theos"
fi

# 2. Dọn dẹp và tạo thư mục tạm
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# 3. Giải nén file deb gốc để lấy Glow.dylib
echo -e "${YELLOW}[*] Đang giải nén file deb gốc...${NC}"
dpkg -x "$ORIG_DEB" "$OUTPUT_DIR/deb_content"
GLOW_DYLIB=$(find "$OUTPUT_DIR/deb_content" -name "Glow.dylib" | head -n 1)

if [ -z "$GLOW_DYLIB" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy Glow.dylib trong file deb gốc!${NC}"
    exit 1
fi
echo -e "${GREEN}[*] Tìm thấy Glow.dylib gốc tại: $GLOW_DYLIB${NC}"

# 4. Biên dịch 00GlowLogger dylib bằng Theos
echo -e "${YELLOW}[*] Đang biên dịch Tweak Logger (00GlowLogger) bằng Theos...${NC}"
cd "$REPO_DIR"
# Dọn dẹp theos cũ và build tweak
rm -rf .theos/
make package FINALPACKAGE=1

# Trích xuất file deb vừa compile chứa 00GlowLogger
VERSION=$(grep "^Version:" "$REPO_DIR/control" | awk '{print $2}')
COMPILED_DEB="$REPO_DIR/packages/com.tommy.glowv3_${VERSION}_iphoneos-arm.deb"

if [ ! -f "$COMPILED_DEB" ]; then
    echo -e "${RED}Lỗi: Biên dịch tweak thất bại, không tìm thấy file deb thành phẩm!${NC}"
    exit 1
fi
echo -e "${GREEN}[*] Biên dịch thành công gói tweak chứa 00GlowLogger!${NC}"

# Trích xuất 00GlowLogger từ deb vừa biên dịch
dpkg -x "$COMPILED_DEB" "$OUTPUT_DIR/our_deb_content"
LOGGER_DYLIB=$(find "$OUTPUT_DIR/our_deb_content" -name "00GlowLogger.dylib" | head -n 1)
LOGGER_PLIST=$(find "$OUTPUT_DIR/our_deb_content" -name "00GlowLogger.plist" | head -n 1)

if [ -z "$LOGGER_DYLIB" ] || [ -z "$LOGGER_PLIST" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy 00GlowLogger dylib/plist trong file deb!${NC}"
    exit 1
fi

# 5. Đóng gói hai thư mục deb riêng biệt để tiêm tự động bằng cyan
echo -e "${YELLOW}[*] Chuẩn bị các gói deb tạm để tiêm...${NC}"

# Tạo deb cho Logger của chúng ta
LOGGER_DEB_DIR="$OUTPUT_DIR/logger_deb"
mkdir -p "$LOGGER_DEB_DIR/DEBIAN"
mkdir -p "$LOGGER_DEB_DIR/Library/MobileSubstrate/DynamicLibraries"
cp "$LOGGER_DYLIB" "$LOGGER_DEB_DIR/Library/MobileSubstrate/DynamicLibraries/00GlowLogger.dylib"
cp "$LOGGER_PLIST" "$LOGGER_DEB_DIR/Library/MobileSubstrate/DynamicLibraries/00GlowLogger.plist"

cat <<EOF > "$LOGGER_DEB_DIR/DEBIAN/control"
Package: com.tommy.glowlogger
Name: 00GlowLogger
Version: ${VERSION}
Architecture: iphoneos-arm
Description: Logger tweak loading before Glow to intercept MSHookMessageEx
Maintainer: tommy
Section: Tweaks
EOF

# Tạo deb cho Glow gốc
GLOW_DEB_DIR="$OUTPUT_DIR/glow_deb"
mkdir -p "$GLOW_DEB_DIR/DEBIAN"
mkdir -p "$GLOW_DEB_DIR/Library/MobileSubstrate/DynamicLibraries"
cp "$GLOW_DYLIB" "$GLOW_DEB_DIR/Library/MobileSubstrate/DynamicLibraries/Glow.dylib"

# Kiểm tra nếu tweak gốc có plist đi kèm
ORIG_PLIST=$(find "$OUTPUT_DIR/deb_content" -name "Glow.plist" | head -n 1)
if [ -n "$ORIG_PLIST" ]; then
    cp "$ORIG_PLIST" "$GLOW_DEB_DIR/Library/MobileSubstrate/DynamicLibraries/Glow.plist"
else
    cat <<EOF > "$GLOW_DEB_DIR/Library/MobileSubstrate/DynamicLibraries/Glow.plist"
{ Filter = { Bundles = ( "com.facebook.Facebook" ); }; }
EOF
fi

cat <<EOF > "$GLOW_DEB_DIR/DEBIAN/control"
Package: com.dvntm.glow
Name: Glow Original Tweak
Version: 1.3.1
Architecture: iphoneos-arm
Description: Original Glow Tweak
Maintainer: dvntm
Section: Tweaks
EOF

# Đóng gói
dpkg-deb -b "$LOGGER_DEB_DIR" "$OUTPUT_DIR/logger.deb"
dpkg-deb -b "$GLOW_DEB_DIR" "$OUTPUT_DIR/glow_original.deb"

# 6. Tiêm song song cả 2 tweak vào Facebook IPA bằng cyan
echo -e "${YELLOW}[*] Đang tiêm 00GlowLogger và Glow gốc vào Facebook IPA...${NC}"
mkdir -p "$REPO_DIR/packages"

# Lệnh cyan sẽ tự động tiêm CydiaSubstrate chuẩn vào IPA, 
# 00GlowLogger.dylib (tên xếp đầu bảng chữ cái) sẽ tự động nạp trước và hook Substrate.
cyan -i "$ORIG_IPA" -o "$FINAL_IPA" \
     -u -w -e -d -s \
     -f "$OUTPUT_DIR/logger.deb" \
     -f "$OUTPUT_DIR/glow_original.deb" \
     --overwrite

# 7. Hoàn tất
echo -e "${GREEN}✓ Hoàn tất! IPA gốc đã tích hợp Logger đã được tạo thành công tại: $FINAL_IPA${NC}"
echo -e "${YELLOW}[*] Hướng dẫn sử dụng:${NC}"
echo -e "  1. Cài đặt file IPA $FINAL_IPA trên iOS thông qua TrollStore."
echo -e "  2. Mở ứng dụng Facebook lên để kích hoạt nạp tweak."
echo -e "  3. Tweak 00GlowLogger sẽ tự động load trước, hook các hàm MSHook trong bộ nhớ và ghi log."
echo -e "  4. Mở file log tại: ${BLUE}/var/mobile/Documents/glow.txt${NC} để xem danh sách giải mã class/selector."
echo -e "  5. Tweak gốc sẽ hoạt động bình thường, tuyệt đối KHÔNG CRASH do chúng ta không thay đổi framework hệ thống."

# Dọn dẹp thư mục tạm
rm -rf "$OUTPUT_DIR"

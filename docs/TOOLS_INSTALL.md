# iOS RE Tools — Cài Đặt

> Danh sách tools cần thiết để RE iOS app hiệu quả.
> Phù hợp với Ubuntu 22.04+ (apt) hoặc macOS (brew).
> Đánh dấu ✅ = đã có, ❌ = cần cài.

---

## 1. Tools cơ bản (đã có sẵn trên Linux)

| Tool | Check | Use case |
|------|-------|----------|
| `strings` | `which strings` ✅ | Find ASCII strings in binary |
| `nm` | `which nm` ✅ | List symbols |
| `objdump` | `which objdump` ✅ | Disassemble |
| `grep` | `which grep` ✅ | Search patterns |
| `file` | `which file` ✅ | Identify file types |
| `xxd` / `hexdump` | `which xxd` ✅ | Hex dump |
| `python3` | `which python3` ✅ | Scripts |
| `pip3` | `which pip3` ✅ | Python packages |
| `git` | `which git` ✅ | Source control |
| `make` | `which make` ✅ | Build |

---

## 2. Tools cần cài (Linux apt)

### 2.1. radare2 (đã có ✅) — Disassembler

```bash
which r2 && r2 -v
# Cài nếu cần:
sudo apt install radare2
```

### 2.2. lief ✅ (đã cài qua pip3) — Mach-O parser cho Python

```bash
pip3 install --break-system-packages lief
```

### 2.3. class-dump (Lechium port) — Dump ObjC headers

**Không có sẵn qua apt.** Cài thủ công:

```bash
# Cần macOS để build. Nếu không có macOS, dùng cách dưới.
git clone https://github.com/lechium/classdumpios.git
cd classdumpios
# Mở classdumpios.xcodeproj bằng Xcode
# Build → Export
# Hoặc dùng prebuilt binary (nếu có)
```

**Alternative cho Linux (limited):**

```bash
# nygard/class-dump (cũ, không support iOS 15+)
# Build từ source:
git clone https://github.com/nygard/class-dump.git
cd class-dump
# Cần Xcode/Objective-C compiler

# class-dump-z (Swift, có thể build trên Linux)
git clone https://github.com/ansklyr/classdump-z.git
# Build với Swift compiler
```

**Workaround Linux: dùng Python script tự viết (như `/tmp/dump_fixed.py` trong project này)**

### 2.4. jtool (Jonathan Levin) — Mach-O parser

```bash
# Không có apt package. Build từ source:
git clone https://github.com/ANSSI-FR/jtool.git
cd jtool
# Cần macOS để build
# Có thể tải prebuilt từ https://github.com/ANSSI-FR/jtool/releases
chmod +x jtool
sudo cp jtool /usr/local/bin/
```

### 2.5. otool (Mach-O inspection)

**Trên macOS:** có sẵn (`xcrun otool`).

**Trên Linux:**

```bash
# Cài LLVM toolchain (có llvm-otool)
sudo apt install llvm
which llvm-otool
# Hoặc
sudo apt install binutils-aarch64-linux-gnu
# (cho cross-compile, nhưng không có otool)
```

**Workaround Linux:** dùng `objdump -d` (có sẵn) hoặc `radare2` thay thế.

### 2.6. plutil — Plist editor

```bash
# macOS có sẵn
# Linux:
sudo apt install libplist-utils
# Hoặc Python:
pip3 install --break-system-packages biplist
```

### 2.7. openssl, libplist-dev — Cho binary analysis

```bash
sudo apt install libplist-dev libplist++-dev
```

### 2.8. xxd (hex editor)

```bash
# Đã có sẵn (part of vim) ✅
# Hoặc:
sudo apt install xxd bsdmainutils
```

### 2.9. capstone, keystone (disassembler framework)

```bash
pip3 install --break-system-packages capstone keystone-engine
```

---

## 3. Tools iOS-specific (Build từ source)

### 3.1. Theos (đã có ✅)

```bash
ls /home/tommy/theos/
# Build env cho iOS tweaks
```

### 3.2. cyan (đã có ✅) — IPA injection

```bash
which cyan
# Build:
git clone https://github.com/aspect-build/cyan.git
cd cyan
go build -o cyan
sudo cp cyan /usr/local/bin/
```

### 3.3. TrollStore helper tools

```bash
# Misaka (cross-compile)
# https://github.com/straight-tamago/misaka
# (cho advanced signing, không cần cho project hiện tại)
```

---

## 4. Tools nâng cao (Jailbreak cần cho full power)

### 4.1. frida — Dynamic instrumentation (MẠNH NHẤT)

**Cần jailbreak device.** Linux cài:

```bash
# Python package
pip3 install --break-system-packages frida-tools

# Server (trên iPhone) cài qua Cydia/Sileo
# Search "frida" trong Sileo → Install

# Verify
frida --version
# Test
frida -U -f com.facebook.Facebook6 --no-pause
```

**Nếu chỉ dùng frida server (inject qua SSH):**
- Trên iPhone jailbreak: install `frida` từ Sileo
- Linux: `pip3 install frida-tools`

### 4.2. bfinject — Dylib injection thay thế cyan

```bash
git clone https://github.com/BishopFox/bfinject.git
cd bfinject
xcodebuild  # Cần macOS
# Hoặc dùng prebuilt binary
cp bfinject /usr/local/bin/
```

**Chỉ dùng cho jailbreak device.**

### 4.3. frida-ios-dump — Dump app binary từ device

```bash
pip3 install --break-system-packages frida-ios-dump
# Dùng:
frida-ios-dump -u -p SSH_PASSWORD com.facebook.Facebook6
```

### 4.4. Cycript (legacy) — Interactive ObjC

```bash
# Cài qua Sileo trên iPhone jailbreak
# Trên macOS, dùng qua ssh
# Cycript đã deprecated, frida thay thế
```

---

## 5. iOS Frameworks Headers (Reference)

### 5.1. iOS Runtime Headers (GitHub)

```bash
git clone https://github.com/nicholasgasior/ios-runtime-headers.git ~/ios-runtimes
# Browse headers
ls ~/ios-runtimes/Headers/
```

### 5.2. FLEX source (cho class exploration)

```bash
git clone https://github.com/FLEXTool/FLEX.git ~/FLEX-source
# Reference cho FLEX integration
```

### 5.3. class-dump headers cho iOS versions

```bash
# Headers cho mỗi iOS version (community maintained)
git clone https://github.com/limneos/classdump-dyld.git
# (Source chỉ, cần macOS để build)
```

---

## 6. Cài đặt tất cả trong 1 lệnh (Ubuntu)

```bash
# Cài tất cả apt packages
sudo apt update
sudo apt install -y \
    radare2 \
    binutils \
    libplist-utils \
    libplist-dev \
    libplist++-dev \
    python3-pip \
    python3-venv \
    git \
    make \
    clang \
    llvm \
    cmake \
    bsdmainutils \
    file

# Cài Python packages
pip3 install --break-system-packages \
    lief \
    capstone \
    keystone-engine \
    biplist

# Clone reference repos
mkdir -p ~/re-tools
cd ~/re-tools

git clone https://github.com/lechium/classdumpios.git
git clone https://github.com/nygard/class-dump.git
git clone https://github.com/ANSSI-FR/jtool.git
git clone https://github.com/FLEXTool/FLEX.git
git clone https://github.com/nicholasgasior/ios-runtime-headers.git

echo "Done!"
```

---

## 7. Workflow đề xuất cho iOS RE

### Daily setup (Linux + TrollStore + Decrypted IPA)

```bash
# 1. Setup paths
export THEOS=/home/tommy/theos
export PATH=$PATH:/home/tommy/re-tools/classdumpios/build

# 2. Get binary
FB_BIN=/path/to/facebook.ipa
WORK_DIR=~/work/fb-$(date +%Y%m%d)
mkdir -p $WORK_DIR
unzip -o $FB_BIN -d $WORK_DIR/extracted/

# 3. Quick recon
otool -L $WORK_DIR/extracted/Payload/Facebook.app/Facebook
strings $WORK_DIR/extracted/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework | \
    grep -iE "Sponsor|FeedUnit|FeedEdge" | head

# 4. Run class-dump (nếu có)
# classdumpios -o $WORK_DIR/headers $WORK_DIR/extracted/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework

# 5. Use custom Python parser (nếu không có macOS)
python3 /home/tommy/dump_fixed.py $WORK_DIR/extracted/Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework | head

# 6. Build tweak
cp -r ~/re-tools/FLEX/Classes/ /tmp/flex-classes/  # Reference
cd ~/my-tweak
THEOS=$THEOS make package FINALPACKAGE=1
cyan -i $FB_BIN -o glow.ipa -f ./packages/com.xxx.deb --overwrite -s -d
```

### Advanced (with Jailbreak)

```bash
# Dump binary từ device (nếu bị encrypt)
frida-ios-dump -u -p PASSWORD com.facebook.Facebook6

# Interactive RE
frida -U -f com.facebook.Facebook6 --no-pause
# Trong frida console:
# - objc.classes
# - ObjC.classes.FBMemNewsFeedEdge.$ownMethods()
# - Memory.readPointer(ptr("0x12345"))
```

---

## 8. Tool Priority cho Project Hiện Tại (FB Ad Blocker)

Để cải thiện workflow đã có:

| Priority | Tool | Use case | Effort |
|----------|------|----------|--------|
| HIGH | **leak-class-dump (iOS 15+)** | Dump headers cho version mới | 2-3 giờ build macOS |
| HIGH | **jtool** | Better binary parsing | 1 giờ |
| MED | **otool (llvm)** | Quick binary inspect | 5 min install |
| MED | **better plutil** | Plist inspection | 5 min |
| LOW | **frida** | Runtime introspection | Cần jailbreak |
| LOW | **Ghidra** | Deep RE | 1+ giờ setup |

**Đề xuất: Cài jtool + llvm-otool trước.** 5-10 phút effort, cải thiện đáng kể.

---

## 9. Mac vs Linux cho iOS RE

| Task | Linux | macOS |
|------|-------|-------|
| Build Theos tweak | ✅ Works | ✅ Works |
| class-dump | ⚠️ Limited (use `tools/dump_objc.py`) | ✅ Full |
| Frida | ✅ Works | ✅ Works |
| Static RE (Ghidra/IDA) | ✅ Ghidra | ✅ Both |
| Build FLEX | ❌ Hard | ✅ Easy |
| Build class-dump port | ❌ Hard (use `tools/dump_objc.py`) | ✅ Easy |
| iOS app build/test | ❌ Simulator only | ✅ Real device |

**Recommendation:** Nếu nghiêm túc về iOS tweak dev, đầu tư 1 Mac (refurbished M1 Mac mini ~$300-400). Sẽ tiết kiệm hàng trăm giờ RE.

---

## 10. Custom Tools (Included in This Repo)

`tools/` directory contains Python scripts do tụi mình viết để work-around limitations của standard tools:

| Script | Purpose | Replaces |
|--------|---------|----------|
| `tools/dump_objc.py` | Dump ObjC class/method/ivar | `class-dump` (handles iOS 15+ chained fixups) |
| `tools/binary_diff.py` | Compare 2 binary dumps | Manual diff |
| `tools/strings_grep.py` | Smart string search | `strings \| grep` (with type filtering) |
| `tools/extract_ipa.py` | Extract + analyze IPA | Manual unzip + plist read |

**Read `tools/README.md` for full usage.**

Quick example:
```bash
# Dump all classes with 'FBMemNewsFeedEdge' in name
python3 tools/dump_objc.py /path/to/FBSharedFramework FBMemNewsFeedEdge

# Search for sponsored-related symbols
python3 tools/strings_grep.py /path/to/FBSharedFramework Sponsor --type=class

# Compare 2 versions
python3 tools/dump_objc.py old/fb > old.txt
python3 tools/dump_objc.py new/fb > new.txt
python3 tools/binary_diff.py old.txt new.txt
```

---

## 11. References

- [Theos setup](https://theos.dev/docs/installation)
- [class-dump-iOS guide](https://github.com/limneos/classdump-dyld)
- [Frida iOS guide](https://frida.re/docs/ios/)
- [Ghidra iOS RE](https://ghidra-sre.org/)
- [leak-class-dump-iOS](https://github.com/lechium/classdumpios)
- [iOS RE community](https://www.reddit.com/r/jailbreakdevelopers/)
- [Custom tools in this repo](tools/README.md)

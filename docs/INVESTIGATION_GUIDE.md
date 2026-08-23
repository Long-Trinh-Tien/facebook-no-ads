# Facebook iOS Tweak Development — Investigation Guide

> File này viết cho người mới bắt đầu muốn hiểu **tư duy RE iOS tweak**, không phải chỉ copy-paste code.
> Tất cả ví dụ lấy từ Glow clone project (chặn ads Facebook 560.x).

---

## Mục lục
1. [Các phương pháp RE phổ biến](#1-các-phương-pháp-reverse-engineering-phổ-biến)
2. [Phương pháp chúng ta dùng & tại sao](#2-phương-pháp-chúng-ta-đã-dùng--tại-sao)
3. [Tư duy từng giai đoạn](#3-tư-duy-từng-giai-đoạn-của-dự-án-này)
4. [Công cụ & khi nào dùng](#4-công-cụ--khi-nào-dùng)
5. [Bài học rút ra](#5-bài-học-rút-ra)
6. [Glossary](#6-glossary)

---

## 1. Các phương pháp Reverse Engineering phổ biến

### 1.1. **Brute-force Runtime Introspection**
**Cách làm:** Inject code vào app, tại runtime gọi `objc_getClassList`, `class_copyMethodList`, `ivar_getOffset`... in ra hết.

**Ưu điểm:**
- Không cần hiểu binary
- Chính xác 100% với binary đang chạy (không bị PAC/chained-fixup làm khó)
- Chỉ cần ObjC runtime API + write file

**Nhược điểm:**
- **CHẬM** — mỗi lần chỉ biết được 1 phần, phải test nhiều lần
- **Dễ crash app** — instantiate class có thể gọi `+initialize` chạy code tự destruct
- **Không scale** — nếu binary có 20,000 classes, scan hết → OOM

**Khi nào dùng:** Verification cuối cùng, hoặc khi đã biết class nào cần target.

**Dự án này dùng ở:** `R2.x` (failed), `R3.0-verify` (succeeded cho class list, crash ở pattern search)

---

### 1.2. **Static RE (IDA/Ghidra/radare2 + class-dump)**
**Cách làm:** Mở binary bằng disassembler, đọc class structures, methods, protocols.

**Ưu điểm:**
- Nhanh hơn runtime nhiều lần cho việc hiểu cấu trúc binary
- Có thể search tất cả symbols cùng lúc
- An toàn (không crash app)

**Nhược điểm:**
- Cần tool chuyên dụng (IDA = $$, Ghidra = free nhưng phức tạp)
- **iOS 15+ dùng `LC_DYLD_CHAINED_FIXUPS`** — pointers bị "bóp" high bits (0x1000000, 0x40000) → class-dump cũ fail
- Phải hiểu Mach-O format

**Khi nào dùng:** Đầu tiên, để có overview của binary. Sau đó mới runtime verify.

**Dự án này dùng ở:** String search (finding selectors), binary analysis (tìm `_FBFeedUnitIsSponsored`)

---

### 1.3. **Hybrid: dùng Headers có sẵn**
**Cách làm:** Tìm class-dump headers trên mạng (developer.limneos.net, headers.cynder.me, github.com/lechium) cho version FB tương ứng. Đọc trước khi RE.

**Ưu điểm:**
- **NHANH NHẤT** — không cần RE binary, chỉ cần đọc header
- Cho biết chính xác selector nào tồn tại
- Class-dump headers cho FB đã có sẵn cho iOS 13-16+ (lechium/classdumpios)

**Nhược điểm:**
- Headers có thể outdated (FB update mỗi tuần)
- Không biết được hành vi runtime, chỉ biết interface

**Khi nào dùng:** Ngay khi bắt đầu, trước khi đụng vào binary.

**Dự án này KHÔNG dùng** (vì lúc đầu chưa biết resource này tồn tại).

---

### 1.4. **Open-source Reference (haoict/facebook-no-ads, jacobcxdev/FBSpNOsor)**
**Cách làm:** Đọc code open-source tweak làm cùng mục đích cho version cũ. Adapt cho version mới.

**Ưu điểm:**
- **HIỂU TRIẾT LÝ** ngay lập tức
- Biết class nào từng được dùng
- Biết logic (return nil cho sponsored)

**Nhược điểm:**
- API có thể đã đổi
- Phải reverse thêm để adapt

**Khi nào dùng:** Ngay khi có idea, search github "Facebook no ads tweak" → đọc trước.

**Dự án này dùng ở:** `R3.0` (sau khi pivot) — đọc `haoict/facebook-no-ads/Tweak.xm` → biết approach `initWithFBTree:`.

---

### 1.5. **Cycript / FLEX (Runtime Explorer)**
**Cách làm:** Inject Cycript (legacy) hoặc FLEX vào app. Browse classes/objects UI.

**Ưu điểm:**
- Trực quan — xem class hierarchy, browse methods
- Có UI đẹp
- FLEX có thể instantiate objects safely

**Nhược điểm:**
- **DỄ crash** với classes phức tạp
- FLEX cũ (iOS 12) → phải patch để chạy trên 15+
- Cần inject vào app (TrollStore + tweak) trước

**Khi nào dùng:** Verify nhanh 1 class cụ thể, browse known structure.

**Dự án này thử ở:** R2.0 FLEX dylib — FLEX load OK nhưng view crashes.

---

### 1.6. **Static String Search**
**Cách làm:** `strings binary | grep "SelectorName"` → tìm selector references.

**Ưu điểm:**
- **ĐƠN GIẢN NHẤT** — chỉ cần `strings` command
- Nhanh cho việc tìm method names
- Biết được class nào REFERENCES selector (bằng cách scan method list)

**Nhược điểm:**
- Cần scan toàn binary nếu không biết vị trí
- High bits làm rối khi tính offset

**Khi nào dùng:** Bước đầu tiên của bất kỳ RE nào. Tìm symbols, class names, methods.

**Dự án này dùng xuyên suốt** — strings FB binary → tìm `_FBFeedUnitIsSponsored`, `FBMemNewsFeedEdge`, etc.

---

## 2. Phương pháp chúng ta đã dùng & tại sao

### Tổng hợp journey

| Stage | Approach | Outcome |
|-------|----------|---------|
| R0 (initial) | C hook UIWindow + strstr | **CRASH** — UIWindow approach unstable |
| R1 | C hook cellForItem + scan classes | Class scan crash (5000+ classes) |
| R1.5 | Static RE `_FBFeedUnitIsSponsored` | Found function at offset 0x910d04 |
| R2.x | GOT-read trick to call C function | Hooks fire but `isSponsored(item)` throws exception |
| R2.7 | Class scan + ivar dump (RUNTIME) | **PARTIAL** — chain walk works, but `FBMemFeedStory` GONE |
| R3.0-verify | Runtime introspection tool | **SUCCESS** — found working classes/methods |
| R3.0 | Hook verified methods (log only) | Hooks fire, ads detected |
| R3.1 | Conservative `isAdEdge` | Feed displays but ALL items hidden |
| R3.2 | Add size hooks | Gaps still visible (precomputed layout) |
| R3.3 | Add category trace | **NEW FINDING** — categories: ORGANIC, SPONSORED, FB_SHORTS, ENGAGEMENT |
| **R3.5/v7** | **Hook `FBMemNewsFeedEdge.node`** | **SUCCESS** — no gaps, no breakage |

### Tại sao cuối cùng chọn `node` hook?

1. **Original Glow approach** (haoict fork): `initWithFBTree:` return nil → data layer filter
2. **560.x equivalent**: `node` method trả về feed unit. Nếu nil → không có gì để layout
3. **Khác với hide cell**: hide cell chỉ ẩn visual, layout vẫn allocate. Return nil từ data layer = không bao giờ vào layout
4. **Safer với C++ struct hack**: không cần đụng vào layout binary struct
5. **Aligned với ComponentKit design**: hook đúng abstraction layer (model → component)

---

## 3. Tư duy từng giai đoạn của dự án này

### Phase 1: Tiếp cận sai (R0 - R1)
```
Tư duy sai: "Facebook là UIKit app, hook UIView methods sẽ work"
Reality:   ComponentKit dùng C++ layout, UIView chỉ là wrapper
```
**Bài học:** Luôn xác định framework UI trước. FB dùng ComponentKit, không phải stock UIKit.

### Phase 2: RE đúng hướng (R1.5)
```
Tư duy đúng: "C function _FBFeedUnitIsSponsored phải có, tìm nó"
Reality:   Tìm thấy ở offset 0x910d04, gọi được nhưng gặp PAC/PLT issues
```
**Bài học:** Static RE tốt cho finding symbols, nhưng calling C functions từ tweak phức tạp vì PIE/PAC.

### Phase 3: Brute-force runtime (R2.x)
```
Tư duy đúng: "Walk chain CKDataSourceItem → model → feed unit, check sponsored"
Reality:   C function expects FBFeedUnit, throws exception on CKDataSourceItem
```
**Bài học:** C function wrapper có thể expect type cụ thể. Phải tìm đúng type.

### Phase 4: Runtime introspection (R3.0-verify)
```
Tư duy đúng: "Verify thực tế runtime, đừng đoán"
Reality:   FBMemFeedStory GONE, FBMemFeedUnitIsSponsoredGraphQL selector vẫn có
Reality 2: FBMemNewsFeedEdge chỉ còn 3 methods: node, deduplicationKey, category
```
**Bài học:** VERSION DRIFT. Class dump 2020 không còn đúng cho 2024. PHẢI verify runtime.

### Phase 5: Class-based filter (R3.1 - R3.4)
```
Tư duy gần đúng: "Hook cellForItem, check category, hide"
Reality:   Layout precomputes size, hide cell vẫn chiếm space
Reality 2: _rootLayout là C++ struct, modification rủi ro
```
**Bài học:** ComponentKit precomputes layout. Hide cell visual ≠ hide trong data. Phải filter ở MODEL layer.

### Phase 6: Model-layer filter (R3.5/v7) ✅
```
Tư duy đúng: "Hook node method, return nil cho SPONSORED - tương tự initWithFBTree: cũ"
Reality:   Works! Không gap, không crash
```
**Bài học:** ORIGINAL ARCHITECTURE của Glow (haoict) là đúng. Chỉ cần adapt selector mới.

---

## 4. Công cụ & khi nào dùng

| Công cụ | Khi nào dùng | Free? |
|---------|--------------|-------|
| `strings` | Tìm class/method/selector names | ✅ |
| `radare2` / `r2` | Disassemble binary, find offsets | ✅ |
| `class-dump` (lechium fork) | Dump ObjC headers từ binary | ✅ |
| `cycript` | Legacy runtime explorer | ✅ (but iOS 12 only) |
| `FLEX` (Flipboard) | Runtime UI explorer | ✅ |
| `Ghidra` | Free alternative IDA | ✅ |
| `IDA Pro` | Pro RE | 💰 |
| `frida` | Dynamic instrumentation (cần jailbreak) | ✅ |
| `lief` | Mach-O parser (Python) | ✅ |
| `Theos` | Build iOS tweaks | ✅ |
| `cyan` | Inject dylib vào IPA (TrollStore) | ✅ |
| `logos` (`%hook`) | Preprocessor cho method swizzling | ✅ (part of Theos) |

### Recommended workflow cho dự án tương tự

```
1. Search github open-source similar project
   → Đọc code, hiểu approach
   → Ví dụ: haoict/facebook-no-ads

2. Static analysis với strings + r2
   → Tìm class names, method names
   → Xác nhận API còn tồn tại

3. class-dump binary (lechium fork)
   → Dump headers, lưu lại
   → Search selectors từ open-source project

4. Runtime verification (custom Tweak.x)
   → Inject verifier, list classes/methods
   → Confirm API vẫn hoạt động

5. Build production tweak
   → Dùng Logos + %hook cho clean code
   → Test từng feature độc lập
```

---

## 5. Bài học rút ra

### Lessons from failures

1. **Đừng brute-force quá sớm** — Dành 1h đọc open-source code trước = tiết kiệm 10h RE
2. **UIView hooks không work với ComponentKit** — Phải hook ở model layer
3. **`objc_getClassList` trong constructor crash** — Defer sang main queue
4. **C++ struct modification rủi ro** — Có thể làm hỏng layout binary
5. **Hidden = YES không remove from layout** — Chỉ ẩn visual, vẫn chiếm space
6. **C function calls expect specific types** — `CKDataSourceItem` ≠ `FBFeedUnit`

### Lessons from successes

1. **Open-source reading > brute force** — haoict/facebook-no-ads cho inspiration
2. **Runtime verification > guess** — R3.0-verify confirmed what's actually there
3. **Hook model methods, not cell** — `FBMemNewsFeedEdge.node` is the right hook
4. **Conservative isAdEdge** — Whitelist (ORGANIC, ENGAGEMENT) thay vì blacklist
5. **Single log file** — Dễ debug, dễ share
6. **Skip sections 0,1** — Đó là story tray, composer, không phải ads
7. **Conservative on story seen** — Chỉ block network call, không block local state

### Universal principles

1. **Đọc open-source trước khi RE từ đầu**
2. **Verify API trên runtime, không tin documentation**
3. **Hook ở abstraction layer cao nhất có thể** (model > view)
4. **Brute force introspection cuối cùng, không đầu tiên**
5. **Logs > assertions** — Log mọi thứ, debug dễ hơn
6. **Whitelist > blacklist** khi không chắc chắn
7. **Build incrementally** — Mỗi version làm 1 thứ, verify

---

## 6. Glossary

| Term | Meaning |
|------|---------|
| **Tweak** | iOS dylib injected vào app để modify behavior |
| **Theos** | Build system cho tweaks |
| **Logos** | Preprocessor syntax (`%hook`, `%orig`, `%new`) |
| **Substrate / Substitute** | Cydia runtime hook engine |
| **MSHookMessageEx** | Substrate function để hook ObjC method |
| **Tweak.x / Tweak.xm** | Source file chính của tweak |
| **PLT** | Procedure Linkage Table (used for function calls) |
| **GOT** | Global Offset Table (function pointers) |
| **PIE** | Position Independent Executable |
| **PAC** | Pointer Authentication Code (arm64e) |
| **FBSharedFramework** | Private framework của Facebook |
| **FBMemNewsFeedEdge** | Class chứa feed unit data (đã thay đổi qua versions) |
| **CKDataSource** | ComponentKit data source |
| **UICollectionView** | iOS grid view (FB feed dùng nó) |
| **CKDataSourceItem** | Item trong ComponentKit (wrapper around model) |
| **FBMemFeedUnit** | Generic feed unit (parent of story, ad, etc.) |
| **TikTok/Twitter/X** | Tweak ecosystem cũng có nhưng khác FB |

---

## Appendix A: Architecture của Facebook iOS (560.x)

```
FBNewsFeedViewController
    └── FBNewsFeedCollectionView (UICollectionView)
            └── dataSource: FBComponentCollectionViewDataSource
                    └── _transactionalComponentDataSource
                            └── CKDataSource
                                    └── _state (CKDataSourceState)
                                            └── _sections: NSArray<NSArray<CKDataSourceItem>>
                                                    └── CKDataSourceItem
                                                            ├── _rootLayout (C++ struct với size)
                                                            └── _model: FBSectionComponentDataSourceModel
                                                                    ├── _model: FBFeedFetchedEdge
                                                                    │       └── _edge: FBMemNewsFeedEdge
                                                                    │               ├── node (returns feed unit)
                                                                    │               ├── deduplicationKey
                                                                    │               └── category (ORGANIC, SPONSORED, ...)
                                                                    ├── _context, _componentBlock, ...
                                                                    └── _accessoryModel
```

**Hook points thử nghiệm:**
- ❌ UICollectionView (UIKit, no FB-specific)
- ✅ FBComponentCollectionViewDataSource.cellForItem (verified)
- ❌ _rootLayout.size (C++ struct, risky)
- ✅ FBMemNewsFeedEdge.node (R3.5/v7 - WORKS)

---

## Appendix B: Build & Test Cheat Sheet

### Build
```bash
cd /path/to/glow-v3
THEOS=/home/tommy/theos make package FINALPACKAGE=1

# Inject into Facebook IPA
cyan -i /path/to/facebook.ipa \
     -o /path/to/glow_v7.ipa \
     -f /path/to/glowv7.deb \
     --overwrite -s -d
```

### Install
```bash
# Use TrollStore to install glow_v7.ipa
# Open Files app → /var/mobile/Documents/glow.txt
```

### Debug
- `glow.txt` log: `/var/mobile/Documents/glow.txt`
- Categories seen: ORGANIC, SPONSORED, FB_SHORTS, ENGAGEMENT, MULTI_FB_STORIES_TRAY
- Ad detection: `category == "SPONSORED" || "AD" || "IN_STREAM_AD"`

### Critical env vars
- `getenv("HOME")` returns `/var/mobile`
- Documents folder: `/var/mobile/Documents/`

---

## 7. Updating Tweak for New Facebook Versions

> **Mục đích:** Khi Facebook update (mỗi 1-2 tuần), tránh phải investigate lại từ đầu như đã làm.
> **Triết lý:** Invest NGAY từ đầu vào verifier + automation, sau này update chỉ mất vài phút.

### 7.1. Facebook update thay đổi gì?

| Loại thay đổi | Tần suất | Ví dụ |
|---------------|----------|-------|
| Method signature đổi | Thường xuyên | `initWithFBTree:` → `initWithFBTree_v2:` |
| Class đổi tên | Thường xuyên | `FBMemNewsFeedEdge` → `FBXxxNewsFeedEdge` |
| Category strings đổi | Thỉnh thoảng | `SPONSORED` → `AD` hoặc `PROMOTED` |
| Selector obfuscation | Hiếm | `Bi:` → `Bj:` |
| GraphQL fragment update | Mỗi release | `FBFeedUnitIsSponsoredGraphQLFragment` → v2 |
| Internal structure | Thường xuyên | `_rootLayout` field offset thay đổi |
| Hook target bị xóa | Hiếm | `FBMemFeedStory` (đã xóa) |

### 7.2. Fast Triage Workflow (5-15 phút)

Khi người dùng báo "không hoạt động sau khi update FB":

```
Step 1 (1 min): Build + install glow_verify.ipa (đã có sẵn)
                → Log tự động list classes/methods còn tồn tại

Step 2 (1 min): Đọc /var/mobile/Documents/glow_verify.txt
                → Classes nào MISSING → đã đổi tên
                → Methods nào MISSING → đã đổi signature

Step 3 (3-5 min): Nếu class đổi tên, search binary:
                strings FBSharedFramework | grep -iE "FeedUnit|Feed.*Edge|NewsFeed"
                → Tìm class mới có cùng pattern

Step 4 (2 min): Update Tweak.x với class name mới
                → Đổi objc_getClass("OldName") → "NewName"
                → Đổi selector nếu cần

Step 5 (5 min): Rebuild + test

Tổng: 10-15 phút vs 1-2 ngày nếu investigate từ đầu
```

### 7.3. Update Checklist

Khi FB update, chạy checklist này:

- [ ] Build `glow_verify.ipa` với binary mới
- [ ] Install, đăng nhập, đợi 10s
- [ ] Đọc `glow_verify.txt`:
  - [ ] `FBMemNewsFeedEdge` còn tồn tại? (cần cho ad blocking)
  - [ ] `FBSnacksBucketsSeenStateManager` còn tồn tại? (cần cho seen)
  - [ ] `FBSnacksMediaContainerView` còn? (cho download story)
  - [ ] `FBVideoOverlayPluginComponentBackgroundView` còn? (cho download video)
  - [ ] `FBComponentCollectionViewDataSource` còn? (cho ad hiding backup)
  - [ ] Các methods `_sendSeenThreadIDsWithBucket:session:`, `initWithFBTree:`, `node`, `category` còn?
- [ ] Nếu class đổi tên: search binary bằng pattern
- [ ] Update Tweak.x với class/method names mới
- [ ] Rebuild, test
- [ ] Update version comment trong Tweak.x
- [ ] Commit + push

### 7.4. Version Compatibility Matrix

Maintain table này để track:

```
| FB Version | FBMemNewsFeedEdge | FBSnacksBuckets... | node method | Status |
|------------|-------------------|---------------------|-------------|--------|
| 555.0.0    | ✓                 | ✓                   | ✓           | Tested |
| 560.x      | ✓ (3 methods)     | ✓                   | ✓           | Working |
| 561.x      | ?                 | ?                   | ?           | Unknown |
| 562.x      | ?                 | ?                   | ?           | Unknown |
```

**Khi nào update matrix:** Mỗi khi test trên version mới.

### 7.5. Verifier Tweak — Standard Tool

**`glow_verify.ipa`** (đã build sẵn ở `/home/tommy/test/glow/`) là tool chuẩn:

- Inject vào FB binary
- Tự động dump:
  - 17 target classes (FOUND/MISSING)
  - Methods của mỗi class
  - Ivars của mỗi class
  - 12 pattern searches (MemNewsFeed, FeedUnit, Snacks, etc.)
- Output ra `/var/mobile/Documents/glow_verify.txt`

**Cách dùng:**
```bash
# 1. Copy FB binary mới vào expected location
cp /path/to/new/facebook.ipa /home/tommy/test/glow/facebook.ipa

# 2. Re-inject verifier
cyan -i /home/tommy/test/glow/facebook.ipa \
     -o /home/tommy/test/glow/glow_verify_v2.ipa \
     -f /home/tommy/test/glow/glowverify.deb \
     --overwrite -s -d

# 3. Install, đợi 10s, copy log
# 4. Đọc log → biết class nào còn, class nào mất
```

### 7.6. Automation Ideas (Future)

**A. Auto-detect API changes**

```python
# Script: compare_classes.py
# Input: glow_verify.txt từ 2 versions FB
# Output: list of changes

def parse_log(path):
    classes = {}
    current = None
    for line in open(path):
        if 'FOUND  :' in line:
            current = line.split(':')[1].strip()
            classes[current] = {'methods': [], 'ivars': []}
        elif '[T]' in line and current:
            classes[current]['methods'].append(line.split('[T] ')[1].strip())
        # ...
    return classes

old = parse_log('glow_verify_560.txt')
new = parse_log('glow_verify_561.txt')

print("REMOVED:", set(old) - set(new))
print("ADDED:", set(new) - set(old))
```

**B. Auto-build matrix update**

```python
# Cập nhật VERSION_COMPAT.md tự động
# từ log + version number (lấy từ Info.plist)
```

**C. Smart version detection**

```objc
// Trong Tweak.x, detect FB version tại runtime
NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
NSString *version = [info objectForKey:@"CFBundleShortVersionString"];
LOG("[fb] version=%s\n", version.UTF8String);
```

**D. Fallback hooks**

```objc
// Try multiple class names
NSArray *candidateClasses = @[@"FBMemNewsFeedEdge", @"FBXxxNewsFeedEdge", @"FBNewFeedEdge"];
Class edgeCls = nil;
for (NSString *name in candidateClasses) {
    edgeCls = objc_getClass(name);
    if (edgeCls) {
        LOG("[hook] using class: %s\n", name.UTF8String);
        break;
    }
}
```

### 7.7. Time-Saving Tips

**1. Maintain "known good" snapshot**
```bash
# Save current FB binary + glow.txt as reference
mkdir -p ~/glow-snapshots/560.x
cp /path/to/facebook.ipa ~/glow-snapshots/560.x/
cp glow.txt ~/glow-snapshots/560.x/
```

**2. Don't re-investigate — diff instead**
```bash
# So sánh binary mới với snapshot cũ
diff <(strings ~/glow-snapshots/560.x/FBSharedFramework | sort) \
     <(strings /path/to/new/FBSharedFramework | sort) | head -50
```

**3. Reuse findings**
- Ghi lại class + method + version vào `VERSION_COMPAT.md`
- Mỗi version chỉ cần 5-10 phút check
- Không bao giờ investigate lại từ đầu

**4. Build pipeline chuẩn hóa**
```bash
# Script: build_and_test.sh
#!/bin/bash
set -e
THEOS=/home/tommy/theos make package FINALPACKAGE=1
cp packages/com.tommy.glowv3_1.0.0_iphoneos-arm.deb glowv7.deb
cyan -i facebook.ipa -o glow_v7.ipa -f glowv7.deb --overwrite -s -d
echo "Built glow_v7.ipa"
```

**5. Test trên ít nhất 2 versions**
- Nếu chỉ test 1 version, có thể break ở version khác
- Maintain multiple devices hoặc test trên cùng device với multiple FB versions

### 7.8. Red Flags — Khi nào cần investigate lại

- ❌ Verifier log: 5+ classes MISSING (large refactor)
- ❌ Categories đổi tên hết (e.g., "SPONSORED" → "AD_TYPE_2")
- ❌ Hook methods trả về EXC cho 50%+ items
- ❌ New FB version thay đổi UI architecture hoàn toàn

Nếu thấy red flags, fall back to:
1. Search github cho version mới (có tweak authors update?)
2. Đọc FB changelog (nếu public)
3. Investigate class mới với class-dump + runtime verification

### 7.9. Maintenance Schedule

- **Hàng tuần:** Check FB version có update không (App Store)
- **Khi update:** Chạy verifier (5 min)
- **Nếu broken:** Update tweak theo checklist (10-15 min)
- **Hàng tháng:** Review log, optimize code
- **Mỗi version lớn:** Full regression test

**Time investment vs value:**
- 15 phút update = tiết kiệm 1-2 ngày investigate
- 30 phút setup automation = tiết kiệm nhiều giờ sau này
- 1 giờ viết docs = tiết kiệm nhiều giờ cho chính mình
- Filter bundles: `com.facebook.Facebook`, `com.facebook.Facebook6`

---

## 8. How to Develop Tweaks WITHOUT Reference Headers

> Câu hỏi thường gặp: "Nếu không có open-source project để đọc thì sao?"
> Trả lời ngắn: **Bạn vẫn có thể làm, nhưng tốn nhiều thời gian hơn 5-10x.**
> Dưới đây là workflow từ scratch mà các tweak developers thật sự dùng.

### 8.1. Realistic Expectations

| Tình huống | Thời gian ước tính |
|------------|--------------------|
| Có open-source reference | 1-2 ngày |
| Có class-dump headers | 3-5 ngày |
| Chỉ có binary | 1-2 tuần |
| App obfuscated nặng | 2-4 tuần |

**Đây là lý do:** Tweak developers thường:
- Dùng app mỗi ngày → hiểu behavior
- Đã làm nhiều tweak trước → pattern recognition
- Đọc code open-source của apps khác → hiểu pattern
- Làm việc trong jailbreak community → hỏi được

**Nếu bạn mới:** Hãy bắt đầu với app CÓ reference (như FB) trước, sau đó apply kiến thức sang app khác.

### 8.2. The 10-Step Workflow (No Reference)

Khi bắt đầu với một app mới, không có open-source tweak tương tự:

**Step 1: Recon — Thu thập thông tin cơ bản (30 phút)**

```bash
# Decrypt binary (cần jailbreak device)
# Tool: frida, dumpdecrypted, bagbak

# Get Info.plist
plutil -p Facebook.app/Info.plist | head -30
# → Bundle ID, version, executable name

# Get linked frameworks
otool -L Facebook.app/Facebook
# → Shows system + private frameworks
# → iOS version target, architecture

# Get binary size, sections
otool -h Facebook.app/Facebook
# → Magic, cputype, filetype
```

**Output cần thu:**
- Bundle ID: `com.facebook.Facebook6`
- Version: `560.1.0`
- Architecture: `arm64`
- Frameworks: `FBSharedFramework`, `FBSDKCore`, etc.

**Step 2: Class-dump headers (1-2 giờ)**

```bash
# Install lechium/classdumpios (works for iOS 15+ chained fixups)
git clone https://github.com/lechium/classdumpios
cd classdumpios
# Build for macOS
open classdumpios.xcodeproj
# Product → Archive → Export → run from terminal

# Dump headers
./classdumpios -o headers_dir/ Facebook.app/Facebook
./classdumpios -o headers_dir/ Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework

# Search for interesting classes
grep -r "FBFeedUnit\|Sponsored\|AdUnit" headers_dir/ | head -20
```

**Step 3: Identify UI framework (15 phút)**

```bash
# Search for known framework prefixes
grep -rE "^@(interface|protocol).*?(CKComponent|ASDisplayNode|RCTView|UIView)" headers_dir/ | head

# ComponentKit: CK prefix
#   → Has CKDataSource, CKComponentLayout
#   → Custom data flow, model-based

# AsyncDisplayKit: AS prefix
#   → Has ASViewController, ASCollectionNode
#   → Texture-based rendering

# React Native: RCT prefix
#   → Has RCTBridge, RCTViewManager
#   → JavaScript bridge

# UIKit (default)
#   → UIView, UIViewController
#   → Stock iOS components
```

**Step 4: Find feature-specific classes (1-2 giờ)**

For "remove ads" feature:
```bash
grep -iE "(ad|sponsor|promot|monetiz).*?(cell|view|unit|item)" headers_dir/ | head -20
```

For "story seen disable":
```bash
grep -iE "(seen|view|receipt|state).*?(manage|tracker|controller)" headers_dir/ | head -20
```

For "download media":
```bash
grep -iE "(download|export|share|save).*?(controller|manager|helper)" headers_dir/ | head -20
```

**Step 5: Build a runtime tracer (2-3 giờ)**

Tạo tweak chỉ để log method calls:

```objc
// tracer.x
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_xxx;

static void hooked_xxx(id self, SEL _cmd, ...) {
    LOG("XXX called: self=%s\n", class_getName(object_getClass(self)));
    if (orig_xxx) {
        // call orig
    }
}

%ctor {
    Class cls = objc_getClass("TargetClass");
    if (cls) {
        Method m = class_getInstanceMethod(cls, @selector(targetMethod:));
        if (m) {
            orig_xxx = method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_xxx);
        }
    }
}
```

Install, chạy app, làm action → check log → biết method có fire không.

**Step 6: Identify the "right" hook point (2-4 giờ)**

Cho mỗi feature, có nhiều hook candidates:

```
For "remove ads":
├── Model layer (PREFERRED — no UI artifacts)
│   ├── Hook init methods → return nil
│   ├── Hook validation methods → return false
│   └── Hook category getters → return "ORGANIC"
├── View layer (BACKUP — may have visual artifacts)
│   ├── Hook cellForItem → don't return cell
│   ├── Hook layout → return 0 size
│   └── Hook willDisplay → hide cell
└── Data layer (LAST RESORT)
    └── Hook URLSession to block analytics calls
```

Thử từ trên xuống dưới. Model layer thường work tốt nhất.

**Step 7: Iterate with FLEX or class inspection (1-2 giờ)**

Build on-device inspector (như `glow_verify.ipa`):

```objc
// Verify class exists + has methods
Class cls = objc_getClass("FBSomeClass");
if (cls) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        LOG("  method: %s\n", sel_getName(sel));
    }
    free(methods);
}
```

Inject vào app, đọc log, biết được API surface.

**Step 8: Build prototype, test, iterate (1-3 ngày)**

```objc
// Prototype: hook one method, verify it works
%hook FBSomeClass
- (id)someMethod {
    LOG("[hook] someMethod called\n");
    return %orig;
}
%end
```

Test, nếu OK → thêm method khác → test → repeat.

**Step 9: Add safety, logging, error handling (1-2 giờ)**

```objc
@try {
    // risky hook code
} @catch (NSException *e) {
    LOG("EXC: %s\n", e.reason.UTF8String);
    // fallback
}
```

**Step 10: Polish, document, publish (1 giờ)**

### 8.3. Search Strategy — Tìm Class Quan Trọng

**Bảng từ khóa tìm kiếm theo feature:**

| Feature | Search keywords |
|---------|----------------|
| Ads / sponsored | `ad`, `sponsor`, `promot`, `monetiz`, `impression` |
| Story / reel | `story`, `reel`, `snacks`, `viewer`, `bucket` |
| Download | `download`, `export`, `save`, `share` |
| Privacy / anonymous | `seen`, `receipt`, `state`, `track` |
| Login / auth | `auth`, `login`, `token`, `session` |
| Notification | `notif`, `push`, `alert`, `badge` |
| Theme / dark mode | `theme`, `color`, `style`, `appearance` |
| Hide UI | `hide`, `view`, `header`, `footer`, `composer` |

**Pattern matching cho ObjC conventions:**

```bash
# Class names thường có pattern
# - FB* (Facebook) → "FBFeedUnit", "FBNewsFeed", "FBStory"
# - IG* (Instagram) → "IGFeedItem", "IGDirectMessage"
# - WA* (WhatsApp) → "WAMessage", "WAChat"
# - TT* (TikTok) → "TTVideo", "TTFeedItem"
# - YT* (YouTube) → "YTVideo", "YTPlayer"

# Methods thường theo NS convention
# -init, -dealloc, -copy, -mutableCopy
# -valueForKey:, -setValue:forKey:
# -isEqual:, -hash, -description

# Properties thường có prefix _
# _items, _dataSource, _delegate, _model
```

### 8.4. Reverse Engineering Toolkit (Priority Order)

| Priority | Tool | Use case | Time |
|----------|------|----------|------|
| 1 | `strings` | Quick keyword search | 5 min |
| 2 | `leak-class-dump` (class-dump port for iOS 15+) | Get all headers | 1-2 hr |
| 3 | `otool` | Get binary info, linked frameworks | 10 min |
| 4 | `nm` | List symbols (functions, classes) | 5 min |
| 5 | **Custom runtime tracer** | See what's called when | 2-3 hr |
| 6 | `radare2` / Ghidra | Deep RE, see function logic | hours |
| 7 | `IDA Pro` | Pro RE (paid) | hours |
| 8 | `frida` (jailbreak only) | Most powerful runtime tool | 30 min setup |
| 9 | `leak-cycript` | Interactive ObjC evaluation | 1 hr setup |

**For most tweaks, 1-6 đủ. 7-9 chỉ cần cho obfuscated apps.**

### 8.5. Common Patterns to Look For

**Anti-versioning techniques trong code (cách app detect tweak):**

```objc
// Detection methods
- (BOOL)isJailbroken { ... }
- (BOOL)hasSubstrate { ... }
- (BOOL)hasFrida { ... }
- (NSArray *)suspiciousLibraries { ... }
```

**Nếu app check tweak:** Hook các method này để return NO/false.

**Bypass patterns:**

```objc
// Force-allow injection
%hook SomeValidator
- (BOOL)validate {
    return YES;  // bypass
}
%end
```

**UIView pattern:**

```objc
// Tìm UIView classes
grep -rE "class FB.*View" headers_dir/ | head
// Hoặc tìm controls
grep -rE "class FB.*Button" headers_dir/ | head
```

**Data source pattern:**

```objc
// Tìm data source (datasource/delegate pattern)
grep -rE "dataSource" headers_dir/ | head
// Tìm các class implementing các protocol
grep -r "@protocol" headers_dir/ | head
```

### 8.6. Khi Nào KHÔNG Nên Làm Tweak

Đôi khi từ bỏ là lựa chọn tốt nhất:

- ❌ **App update mỗi ngày** — quá tốn thời gian maintain
- ❌ **Heavy obfuscation** (control flow, string encryption) — gần như không thể RE
- ❌ **App nhỏ, ít user** — ROI thấp
- ❌ **App cạnh tranh có open-source tương tự** — dùng open-source thay vì viết mới
- ❌ **App phát hiện jailbreak/tweak** — bị crack ngay khi install

**Better alternatives:**

- Web app (Tampermonkey userscript) — không cần tweak
- API call intercept (mitmproxy) — chặn network calls
- Modified APK/IPA (for Android) — ít bị phát hiện
- Fork of open-source app — sửa trực tiếp source

### 8.7. Realistic Timeline Example

Tweak "Remove ads trong app X" từ đầu, không có reference:

```
Day 1: Recon + class-dump (3-4 giờ)
  - Decrypt binary
  - Run class-dump
  - Search for "ad", "sponsor" keywords
  - Identify 5-10 candidate classes

Day 2: Build prototype (3-4 giờ)
  - Create Theos project
  - Hook 1-2 candidate methods
  - Test trên device
  - Confirm hooks fire

Day 3-4: Iterate (4-6 giờ/ngày)
  - Try different hook points
  - Test edge cases
  - Handle exceptions
  - Add logging

Day 5: Polish (2-3 giờ)
  - Finalize Tweak.x
  - Add safety checks
  - Test thoroughly
  - Write docs

Total: 15-25 giờ cho working tweak từ scratch
```

So với có reference: **3-5 giờ**. Difference is **5-8x**.

### 8.8. Phương pháp Tiết Kiệm Thời Gian

Khi KHÔNG có reference, làm thế này để nhanh hơn:

**1. Tìm tất cả open-source tweaks tương tự**

```bash
# Search GitHub cho related projects
# Site: github.com
# Keywords:
#   - "{app} tweak"
#   - "{app} no ads"
#   - "{app} downloader"
#   - "iOS tweak {app}"
#   - "cydia {app}"
```

**2. Đọc code apps khác cùng dev team**

```bash
# Facebook team làm FB, IG, WA, Messenger
# → Patterns giống nhau giữa các apps
# → Class names, method signatures tương tự

# ByteDance làm TikTok, Douyin, Resso, CapCut
# → Cùng infrastructure
```

**3. Tìm developer blog/jobs**

```bash
# Search LinkedIn cho "iOS engineer @ {app}"
# Blog posts về architecture
# Job descriptions reveal tech stack
```

**4. Tham gia community**

```bash
# r/jailbreakdevelopers (Reddit)
# iOSJBN Discord
# Twitter: @iOSDevRE, @iOS_research
# GitHub: search for "{app} tweak"
```

**5. Dùng AI/LLM hỗ trợ**

```bash
# LLM có thể:
# - Explain binary structures
# - Suggest class names từ context
# - Generate code từ high-level description
# - Find patterns trong headers

# Nhưng KHÔNG thể:
# - Run code trên device
# - Verify hook points runtime
# - Replace deep RE
```

### 8.9. Khi Nào Open-Source Reference Sẽ Xuất Hiện?

Dù app không có tweak open-source, thường có **related projects**:

- **Forks của apps** (e.g., Messenger, Lite versions) — cùng code base
- **Web wrappers** (Electron, Capacitor) — có thể RE web version thay vì native
- **API docs** (public GraphQL/REST) — hiểu data flow
- **TestFlight betas** — sớm hơn App Store, có thể trước khi obfuscate

**Checklist tìm reference:**

- [ ] GitHub: search "{app} tweak", "{app} no ads", "{app} downloader"
- [ ] Reddit: r/jailbreak, r/jailbreakdevelopers
- [ ] Discord: iOSJBN, tweak development servers
- [ ] Packix, Havoc repos — có tweak nào tương tự?
- [ ] BigBoss, Chariz — Cydia repos có tweak nào?
- [ ] Twitter: search "{app} tweak" với developer accounts
- [ ] App's own GitHub: some apps open-source their SDK
- [ ] App's competitors: similar apps may have open-source tweaks

### 8.10. Minimal Viable Tweak (Khi Mọi Thứ Đều Khó)

Nếu thật sự không thể RE sâu, focus vào **UI-layer hacks đơn giản**:

```objc
// 1. Hide specific known views
%hook FBAdBannerView
- (void)didMoveToSuperview {
    self.hidden = YES;
    [self removeFromSuperview];
}
%end

// 2. Block specific URLs
%hook NSURLSession
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)cfg {
    // block tracking endpoints
    return %orig;
}
%end

// 3. Block specific notifications
%hook UIPasteboard
+ (void)setGeneralPasteboard:(UIPasteboard *)pb {
    // do nothing
}
%end
```

**Minimal tweak = working at basic level, even if not perfect.**

### Summary

**Không có reference ≠ không thể làm tweak.** Chỉ cần:
1. class-dump binary (1-2 giờ)
2. Search cho feature keywords (1-2 giờ)
3. Build runtime tracer (2-3 giờ)
4. Iterate hooks (1-3 ngày)
5. Polish + test (1 ngày)

Total: 15-25 giờ thay vì 3-5 giờ với reference.

**Trade-off:** Thời gian vs độ chính xác. Reference cho phép bạn đi đúng hướng ngay, scratch buộc bạn khám phá.

**Recommendation:** 
- Bắt đầu với apps CÓ reference (FB, YT, TikTok — đều có tweak open-source)
- Apply kiến thức sang apps KHÔNG có reference
- Chia sẻ findings của bạn — trở thành reference cho người khác


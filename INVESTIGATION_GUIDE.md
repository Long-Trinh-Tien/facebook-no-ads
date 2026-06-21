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
- Filter bundles: `com.facebook.Facebook`, `com.facebook.Facebook6`

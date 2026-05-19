// Stage R1.5 — Dual-Function Passive Correlation Telemetry
// NO mutation. NO GOT. NO trampoline. NO UIKit changes.
// Hooks: willDisplayCell. Observes: _FBFeedUnitIsSponsored + _FBSponsoredDataObjectsForFeedUnit.
// Logs: class hierarchy, caller addr, YES/NO counts, sponsored data objects.

#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

// ─── Globals ───
static IMP orig_viewDidAppear = NULL;
static IMP orig_willDisplayCell = NULL;
static id glowDS = nil;
static BOOL glowSetupDone = NO;
static BOOL glowButtonAttached = NO;

// dlsym'd function pointers
typedef bool (*FBFeedUnitIsSponsoredFunc)(id);
typedef id  (*FBSponsoredDataObjectsForFeedUnitFunc)(id);
static FBFeedUnitIsSponsoredFunc isSponsored = NULL;
static FBSponsoredDataObjectsForFeedUnitFunc sponDataObjects = NULL;

// Telemetry counters
static int total_checks = 0;
static int yes_count = 0;
static int no_count = 0;

// ─── Log helper ───
static FILE *logfile = NULL;
static void log_open(void) {
    if (logfile) return;
    const char *home = getenv("HOME");
    if (!home) return;
    char path[512];
    snprintf(path, sizeof(path), "%s/Documents/glow_corr.txt", home);
    logfile = fopen(path, "w");
    if (logfile) {
        fprintf(logfile, "Stage R1.5 — Dual-Function Passive Telemetry\n");
        fprintf(logfile, "isSponsored=        %p\n", (void*)isSponsored);
        fprintf(logfile, "sponDataObjects=    %p\n", (void*)sponDataObjects);
        fprintf(logfile, "\n");
    }
}
#define LOG(...) do { log_open(); if (logfile) { fprintf(logfile, __VA_ARGS__); fflush(logfile); } } while(0)

// ─── Helper: log a return address via dladdr ───
static void logCallerAt0(FILE *f) {
    void *ret = __builtin_return_address(0);
    if (!ret) return;
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr(ret, &info) && info.dli_sname) {
        ptrdiff_t offset = (char*)ret - (char*)info.dli_saddr;
        fprintf(f, " caller0=%s+0x%lx", info.dli_sname, (long)offset);
    } else {
        fprintf(f, " caller0=%p", ret);
    }
}

// ─── Helper: log full class hierarchy ───
static void logClassHierarchy(FILE *f, id obj) {
    Class cls = object_getClass(obj);
    int depth = 0;
    while (cls && depth < 8) {
        fprintf(f, "%s%s", depth == 0 ? "" : " <- ", class_getName(cls));
        cls = class_getSuperclass(cls);
        depth++;
    }
}

// ─── Helper: get feed item from CKDataSourceState by indexPath ───
static id getFeedItemAtIndexPath(id datasource, NSIndexPath *ip) {
    if (!datasource || !ip) return nil;
    Ivar tcdsIvar = class_getInstanceVariable(object_getClass(datasource), "_transactionalComponentDataSource");
    if (!tcdsIvar) return nil;
    id tcds = nil;
    @try { tcds = object_getIvar(datasource, tcdsIvar); } @catch (...) { return nil; }
    if (!tcds) return nil;
    Ivar dsIvar = class_getInstanceVariable(object_getClass(tcds), "_dataSource");
    if (!dsIvar) return nil;
    id ckds = nil;
    @try { ckds = object_getIvar(tcds, dsIvar); } @catch (...) { return nil; }
    if (!ckds) return nil;
    Ivar stateIvar = class_getInstanceVariable(object_getClass(ckds), "_state");
    if (!stateIvar) return nil;
    id state = nil;
    @try { state = object_getIvar(ckds, stateIvar); } @catch (...) { return nil; }
    if (!state) return nil;
    Ivar secIvar = class_getInstanceVariable(object_getClass(state), "_sections");
    if (!secIvar) return nil;
    id sections = nil;
    @try { sections = object_getIvar(state, secIvar); } @catch (...) { return nil; }
    if (!sections || ![sections isKindOfClass:[NSArray class]]) return nil;

    NSArray *sa = (NSArray *)sections;
    if (ip.section < 0 || ip.section >= (NSInteger)sa.count) return nil;
    id section = sa[ip.section];
    if (![section isKindOfClass:[NSArray class]]) return nil;
    NSArray *items = (NSArray *)section;
    if (ip.row < 0 || ip.row >= (NSInteger)items.count) return nil;
    return items[ip.row];
}

// ─── Initial section dump ───
static void logInitialSections(id datasource) {
    if (!datasource || !isSponsored) return;
    Ivar tcdsIvar = class_getInstanceVariable(object_getClass(datasource), "_transactionalComponentDataSource");
    if (!tcdsIvar) return;
    id tcds = nil;
    @try { tcds = object_getIvar(datasource, tcdsIvar); } @catch (...) { return; }
    if (!tcds) return;
    Ivar dsIvar = class_getInstanceVariable(object_getClass(tcds), "_dataSource");
    if (!dsIvar) return;
    id ckds = nil;
    @try { ckds = object_getIvar(tcds, dsIvar); } @catch (...) { return; }
    if (!ckds) return;
    Ivar stateIvar = class_getInstanceVariable(object_getClass(ckds), "_state");
    if (!stateIvar) return;
    id state = nil;
    @try { state = object_getIvar(ckds, stateIvar); } @catch (...) { return; }
    if (!state) return;
    Ivar secIvar = class_getInstanceVariable(object_getClass(state), "_sections");
    if (!secIvar) return;
    id sections = nil;
    @try { sections = object_getIvar(state, secIvar); } @catch (...) { return; }
    if (!sections || ![sections isKindOfClass:[NSArray class]]) return;

    NSArray *sa = (NSArray *)sections;
    LOG("=== INITIAL SECTION DUMP ===\n");
    LOG("sections=%lu\n\n", (unsigned long)sa.count);
    for (NSUInteger s = 0; s < sa.count; s++) {
        id section = sa[s];
        if (![section isKindOfClass:[NSArray class]]) continue;
        NSArray *items = (NSArray *)section;
        LOG("section[%lu] count=%lu\n", (unsigned long)s, (unsigned long)items.count);
        for (NSUInteger r = 0; r < items.count && r < 50; r++) {
            id item = items[r];
            bool sp = false;
            @try { sp = isSponsored(item); } @catch (...) {}

            LOG("  [%lu,%lu] ", (unsigned long)s, (unsigned long)r);
            logClassHierarchy(logfile, item);

            if (sponDataObjects) {
                id objs = nil;
                @try { objs = sponDataObjects(item); } @catch (...) {}
                if (objs && [objs isKindOfClass:[NSArray class]]) {
                    LOG(" sponData=%luobj", (unsigned long)[(NSArray *)objs count]);
                } else if (objs) {
                    LOG(" sponData=%s", NSStringFromClass([objs class]).UTF8String);
                }
            }

            LOG(" sp=%s\n", sp ? "YES***" : "NO");
        }
    }
    LOG("=== END DUMP ===\n\n");
}

// ─── willDisplayCell hook ───
static void hooked_willDisplayCell(id self, SEL _cmd, UICollectionView *cv, UICollectionViewCell *cell, NSIndexPath *ip) {
    if (orig_willDisplayCell)
        ((void(*)(id,SEL,UICollectionView*,UICollectionViewCell*,NSIndexPath*))orig_willDisplayCell)(self, _cmd, cv, cell, ip);

    if (!isSponsored || !glowDS) return;

    id item = getFeedItemAtIndexPath(glowDS, ip);
    if (!item) return;

    NSString *cellCls = NSStringFromClass([cell class]);
    NSString *reuseId = [cell respondsToSelector:@selector(reuseIdentifier)] ? [cell performSelector:@selector(reuseIdentifier)] : @"?";

    bool sp = false;
    @try { sp = isSponsored(item); } @catch (NSException *e) {
        LOG("EXCEPTION at [%ld,%ld]: %s\n", (long)ip.section, (long)ip.row, e.reason.UTF8String);
        return;
    } @catch (...) { return; }

    total_checks++;
    if (sp) yes_count++; else no_count++;

    LOG("WILL_DISPLAY [%ld,%ld]", (long)ip.section, (long)ip.row);
    LOG(" cell=%s", cellCls.UTF8String);
    LOG(" reuse=%s", [reuseId UTF8String]);
    LOG(" item="); logClassHierarchy(logfile, item);
    LOG(" sp=%s", sp ? "YES***AD***" : "NO");

    if (sponDataObjects) {
        id objs = nil;
        @try { objs = sponDataObjects(item); } @catch (...) {}
        if (objs && [objs isKindOfClass:[NSArray class]]) {
            LOG(" sponData=%luobj", (unsigned long)[(NSArray *)objs count]);
        } else if (objs) {
            LOG(" sponData=%s", NSStringFromClass([objs class]).UTF8String);
        }
    }

    // Log caller chain (willDisplayCell was called by UIKit)
    logCallerAt0(logfile);
    LOG(" YES=%d NO=%d\n", yes_count, no_count);
}

// ─── Button tap ───
static void glowButtonTapped(id self, SEL _cmd, id sender) {
    LOG("=== BUTTON TAP ===\n");
    if (glowDS) logInitialSections(glowDS);
    LOG("Total: checks=%d YES=%d NO=%d\n", total_checks, yes_count, no_count);
}

// ─── viewDidAppear hook ───
static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear)
        ((void(*)(id,SEL,BOOL))orig_viewDidAppear)(self, _cmd, animated);

    const char *className = class_getName(object_getClass(self));
    UIViewController *vc = (UIViewController *)self;

    if (className && strstr(className, "FBNewsFeedViewController")) {
        for (UIView *sub in vc.view.subviews) {
            NSString *subCls = NSStringFromClass([sub class]);
            if ([subCls containsString:@"FBNewsFeedCollectionView"] && [sub isKindOfClass:[UICollectionView class]]) {
                UICollectionView *cv = (UICollectionView *)sub;
                id ds = cv.dataSource;
                if (!ds) break;
                if (!glowSetupDone) {
                    glowSetupDone = YES;
                    glowDS = ds;
                    SEL wdcSel = @selector(collectionView:willDisplayCell:forItemAtIndexPath:);
                    Method wdcM = class_getInstanceMethod(object_getClass(ds), wdcSel);
                    if (wdcM) {
                        orig_willDisplayCell = method_getImplementation(wdcM);
                        method_setImplementation(wdcM, (IMP)hooked_willDisplayCell);
                        LOG("HOOK: collectionView:willDisplayCell:forItemAtIndexPath:\n");
                    } else {
                        LOG("ERROR: willDisplayCell not found on %s\n", NSStringFromClass([ds class]).UTF8String);
                    }
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        logInitialSections(ds);
                    });
                }
                break;
            }
        }
    }

    if (glowButtonAttached) return;
    UIView *view = vc.view;
    if (!view || !vc.isViewLoaded || !view.window) return;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 60, 60);
    button.backgroundColor = [UIColor blueColor];
    [button setTitle:@"GLOW" forState:UIControlStateNormal];
    class_addMethod([vc class], @selector(glowBtn:), (IMP)glowButtonTapped, "v@:@");
    [button addTarget:vc action:@selector(glowBtn:) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];
    glowButtonAttached = YES;
}

// ─── Constructor ───
__attribute__((constructor))
static void glow_init(void) {
    const char *home = getenv("HOME");
    if (!home) return;

    char path[512];
    snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "Stage R1.5 — Dual-Function Passive Telemetry\n\n");

    isSponsored = dlsym(RTLD_DEFAULT, "_FBFeedUnitIsSponsored");
    fprintf(f, "dlsym _FBFeedUnitIsSponsored: %p (%s)\n",
            (void*)isSponsored, isSponsored ? "OK" : dlerror());

    sponDataObjects = dlsym(RTLD_DEFAULT, "_FBSponsoredDataObjectsForFeedUnit");
    fprintf(f, "dlsym _FBSponsoredDataObjectsForFeedUnit: %p (%s)\n",
            sponDataObjects, sponDataObjects ? "OK" : dlerror());

    fprintf(f, "\nNative caller addrs (from static RE):\n");
    fprintf(f, "  0x1000c2814 0x1000cfe00 0x1000e0280\n");
    fprintf(f, "  0x100421fa8 0x100424264 0x100424858\n");
    fprintf(f, "  0x10063bdb0 0x10063fdc8 0x10063ff9c\n");
    fprintf(f, "  0x1006411b8\n\n");

    Class vcClass = objc_getClass("UIViewController");
    SEL vdaSel = @selector(viewDidAppear:);
    Method vdaM = class_getInstanceMethod(vcClass, vdaSel);
    if (vdaM) {
        orig_viewDidAppear = method_getImplementation(vdaM);
        method_setImplementation(vdaM, (IMP)hooked_viewDidAppear);
        fprintf(f, "HOOK: UIViewController.viewDidAppear:\n");
    }
    fclose(f);
}

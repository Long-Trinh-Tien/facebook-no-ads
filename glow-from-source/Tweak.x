// Stage R1 — Passive Correlation Telemetry
// NO mutation. NO GOT. NO trampoline. NO UIKit changes.
// Only observe: willDisplayCell + _FBFeedUnitIsSponsored → log correlation.

#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

// ─── Globals ───
static IMP orig_viewDidAppear = NULL;
static IMP orig_willDisplayCell = NULL;
static id glowDS = nil;                    // retained datasource ref
static BOOL glowSetupDone = NO;
static BOOL glowButtonAttached = NO;

// dlsym'd function pointer
typedef bool (*FBFeedUnitIsSponsoredFunc)(id);
static FBFeedUnitIsSponsoredFunc isSponsored = NULL;

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
        fprintf(logfile, "Stage R1 — Passive Correlation Telemetry\n");
        fprintf(logfile, "isSponsored dlsym: %p\n\n", (void*)isSponsored);
    }
}
#define LOG(...) do { log_open(); if (logfile) { fprintf(logfile, __VA_ARGS__); fflush(logfile); } } while(0)

// ─── CKDataSourceState section dumper (for initial dump only) ───
static void logInitialSections(id datasource) {
    if (!datasource || !isSponsored) return;

    // Walk: datasource → _transactionalComponentDataSource → _dataSource → _state
    Ivar tcdsIvar = class_getInstanceVariable(object_getClass(datasource), "_transactionalComponentDataSource");
    if (!tcdsIvar) return;
    id tcds = nil;
    @try { tcds = object_getIvar(datasource, tcdsIvar); } @catch (...) {}
    if (!tcds) return;

    Ivar dsIvar = class_getInstanceVariable(object_getClass(tcds), "_dataSource");
    if (!dsIvar) return;
    id ckds = nil;
    @try { ckds = object_getIvar(tcds, dsIvar); } @catch (...) {}
    if (!ckds) return;

    Ivar stateIvar = class_getInstanceVariable(object_getClass(ckds), "_state");
    if (!stateIvar) return;
    id state = nil;
    @try { state = object_getIvar(ckds, stateIvar); } @catch (...) {}
    if (!state) return;

    Ivar secIvar = class_getInstanceVariable(object_getClass(state), "_sections");
    if (!secIvar) return;
    id sections = nil;
    @try { sections = object_getIvar(state, secIvar); } @catch (...) {}
    if (!sections || ![sections isKindOfClass:[NSArray class]]) return;

    NSArray *sa = (NSArray *)sections;
    LOG("=== INITIAL SECTION DUMP (feed loaded) ===\n");
    LOG("sections: %lu\n", (unsigned long)sa.count);

    for (NSUInteger s = 0; s < sa.count; s++) {
        id section = sa[s];
        if (![section isKindOfClass:[NSArray class]]) continue;
        NSArray *items = (NSArray *)section;
        LOG("  section[%lu]: %lu items\n", (unsigned long)s, (unsigned long)items.count);

        for (NSUInteger r = 0; r < items.count && r < 50; r++) {
            id item = items[r];
            NSString *cls = NSStringFromClass([item class]);
            bool sp = false;
            @try { sp = isSponsored(item); } @catch (...) {}

            LOG("    [%lu,%lu] %s sponsored=%s\n",
                (unsigned long)s, (unsigned long)r,
                cls.UTF8String, sp ? "YES" : "NO");
        }
    }
    LOG("=== END INITIAL DUMP ===\n\n");
}

// ─── willDisplayCell hook ───
// Called when a cell is about to appear on screen.
// We use the indexPath to look up the feed item and call the predicate.
static void hooked_willDisplayCell(id self, SEL _cmd, UICollectionView *cv, UICollectionViewCell *cell, NSIndexPath *ip) {
    if (orig_willDisplayCell)
        ((void(*)(id,SEL,UICollectionView*,UICollectionViewCell*,NSIndexPath*))orig_willDisplayCell)(self, _cmd, cv, cell, ip);

    if (!isSponsored || !glowDS) return;

    // Get feed item from CKDataSourceState at this indexPath
    Ivar tcdsIvar = class_getInstanceVariable(object_getClass(glowDS), "_transactionalComponentDataSource");
    if (!tcdsIvar) return;
    id tcds = nil;
    @try { tcds = object_getIvar(glowDS, tcdsIvar); } @catch (...) {}
    if (!tcds) return;

    Ivar dsIvar = class_getInstanceVariable(object_getClass(tcds), "_dataSource");
    if (!dsIvar) return;
    id ckds = nil;
    @try { ckds = object_getIvar(tcds, dsIvar); } @catch (...) {}
    if (!ckds) return;

    Ivar stateIvar = class_getInstanceVariable(object_getClass(ckds), "_state");
    if (!stateIvar) return;
    id state = nil;
    @try { state = object_getIvar(ckds, stateIvar); } @catch (...) {}
    if (!state) return;

    Ivar secIvar = class_getInstanceVariable(object_getClass(state), "_sections");
    if (!secIvar) return;
    id sections = nil;
    @try { sections = object_getIvar(state, secIvar); } @catch (...) {}
    if (!sections || ![sections isKindOfClass:[NSArray class]]) return;

    NSArray *sa = (NSArray *)sections;
    NSInteger sectionIdx = ip.section;
    NSInteger rowIdx = ip.row;

    if (sectionIdx < 0 || sectionIdx >= (NSInteger)sa.count) return;
    id section = sa[sectionIdx];
    if (![section isKindOfClass:[NSArray class]]) return;
    NSArray *items = (NSArray *)section;
    if (rowIdx < 0 || rowIdx >= (NSInteger)items.count) return;

    id item = items[rowIdx];
    if (!item) return;

    NSString *itemCls = NSStringFromClass([item class]);
    NSString *cellCls = NSStringFromClass([cell class]);
    NSString *reuseId = [cell respondsToSelector:@selector(reuseIdentifier)] ? [cell performSelector:@selector(reuseIdentifier)] : @"?";

    bool sp = false;
    @try { sp = isSponsored(item); } @catch (NSException *e) {
        LOG("WILL_DISPLAY_CELL EXCEPTION: %s\n", e.reason.UTF8String);
        return;
    } @catch (...) {
        return;
    }

    LOG("WILL_DISPLAY_CELL [%ld,%ld] item=%s cell=%s reuse=%s sponsored=%s\n",
        (long)sectionIdx, (long)rowIdx,
        itemCls.UTF8String, cellCls.UTF8String,
        [reuseId UTF8String],
        sp ? "YES***AD***" : "NO");
}

// ─── Button tap re-dump ───
static void glowButtonTapped(id self, SEL _cmd, id sender) {
    LOG("=== BUTTON TAP — re-dump ===\n");
    if (glowDS) logInitialSections(glowDS);
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
                        LOG("ERROR: willDisplayCell method NOT FOUND on %s\n", NSStringFromClass([ds class]).UTF8String);
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

// ─── Constructor — NO mutation, only dlsym + ObjC hooks ───
__attribute__((constructor))
static void glow_init(void) {
    const char *home = getenv("HOME");
    if (!home) return;

    // Open initial file for dlsym results
    char path[512];
    snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "Stage R1 — Passive Correlation Telemetry\n\n");

    // dlsym _FBFeedUnitIsSponsored (NO hooking, NO patching)
    isSponsored = dlsym(RTLD_DEFAULT, "_FBFeedUnitIsSponsored");
    fprintf(f, "dlsym _FBFeedUnitIsSponsored: %p (%s)\n",
            (void*)isSponsored, isSponsored ? "OK" : dlerror());

    // dlsym _FBSponsoredDataObjectsForFeedUnit (secondary target)
    void *sponData = dlsym(RTLD_DEFAULT, "_FBSponsoredDataObjectsForFeedUnit");
    fprintf(f, "dlsym _FBSponsoredDataObjectsForFeedUnit: %p (%s)\n",
            sponData, sponData ? "OK" : dlerror());

    // Hook viewDidAppear (UIKit — always safe)
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

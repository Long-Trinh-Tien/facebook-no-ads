// Stage R3.5/v7 — Practical approach
// 1. Try hooking FBMemNewsFeedEdge.node to return nil for sponsored
//    (similar to original Glow's initWithFBTree: approach)
// 2. Keep cell hiding as backup
// 3. Hook 4 story seen paths in FBSnacksBucketsSeenStateManager
// 4. Skip sections 0/1 (story tray, composer)
//
// All output to /var/mobile/Documents/glow.txt
// Filename: glow_v7.ipa

#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>

static char g_log_path[512] = {0};
static void log_msg(const char *fmt, ...) {
    if (g_log_path[0] == 0) {
        const char *home = getenv("HOME");
        if (!home) home = "/var/mobile";
        snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow.txt", home);
    }
    FILE *f = fopen(g_log_path, "a");
    if (!f) f = fopen("/var/mobile/Documents/glow.txt", "a");
    if (f) {
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fclose(f);
    }
}
#define LOG(fmt, ...) log_msg(fmt, ##__VA_ARGS__)

// ─── Hook FBMemNewsFeedEdge.node — return nil for SPONSORED ───
// This is the closest analog to old initWithFBTree: returning nil
// prevents the layout from being computed for this edge.
static IMP orig_node = NULL;
static int node_blocked = 0;

static id hooked_node(id self, SEL _cmd) {
    // Call orig first to get the actual node
    id result = nil;
    if (orig_node) {
        typedef id (*FnType)(id, SEL);
        FnType fn = (FnType)(uintptr_t)orig_node;
        result = fn(self, _cmd);
    }
    // Check category
    @try {
        SEL catSel = sel_registerName("category");
        if ([self respondsToSelector:catSel]) {
            id cat = [self performSelector:catSel];
            if ([cat isKindOfClass:[NSString class]]) {
                NSString *cs = (NSString *)cat;
                if ([cs isEqualToString:@"SPONSORED"] ||
                    [cs isEqualToString:@"AD"] ||
                    [cs isEqualToString:@"IN_STREAM_AD"]) {
                    node_blocked++;
                    if (node_blocked <= 3 || (node_blocked % 20) == 0) {
                        LOG("[node] blocked SPONSORED edge (count=%d)\n", node_blocked);
                    }
                    return nil;
                }
            }
        }
    } @catch (...) {}
    return result;
}

// ─── Walk to FBMemNewsFeedEdge ───
static id getMemEdge(id self, NSIndexPath *ip) {
    if (!self || !ip) return nil;
    @try {
        Class dsCls = object_getClass(self);
        Ivar tcdsIvar = class_getInstanceVariable(dsCls, "_transactionalComponentDataSource");
        if (!tcdsIvar) return nil;
        id tcds = object_getIvar(self, tcdsIvar);
        if (!tcds) return nil;
        Class tcdsCls = object_getClass(tcds);
        Ivar dsIvar = class_getInstanceVariable(tcdsCls, "_dataSource");
        if (!dsIvar) return nil;
        id ckds = object_getIvar(tcds, dsIvar);
        if (!ckds) return nil;
        Class ckdsCls = object_getClass(ckds);
        Ivar stateIvar = class_getInstanceVariable(ckdsCls, "_state");
        if (!stateIvar) return nil;
        id state = object_getIvar(ckds, stateIvar);
        if (!state) return nil;
        Class stateCls = object_getClass(state);
        Ivar secIvar = class_getInstanceVariable(stateCls, "_sections");
        if (!secIvar) return nil;
        id sections = object_getIvar(state, secIvar);
        if (![sections isKindOfClass:[NSArray class]]) return nil;
        NSArray *sa = (NSArray *)sections;
        if (ip.section < 0 || ip.section >= (NSInteger)sa.count) return nil;
        id section = sa[ip.section];
        if (![section isKindOfClass:[NSArray class]]) return nil;
        NSArray *items = (NSArray *)section;
        if (ip.row < 0 || ip.row >= (NSInteger)items.count) return nil;
        id item = items[ip.row];
        if (!item) return nil;
        Class itemCls = object_getClass(item);
        Ivar modelIvar = class_getInstanceVariable(itemCls, "_model");
        if (!modelIvar) return nil;
        id model = object_getIvar(item, modelIvar);
        if (!model) return nil;
        Class modelCls = object_getClass(model);
        Ivar modelIvar2 = class_getInstanceVariable(modelCls, "_model");
        if (!modelIvar2) return nil;
        id feedEdgeWrapper = object_getIvar(model, modelIvar2);
        if (!feedEdgeWrapper) return nil;
        Class edgeCls = object_getClass(feedEdgeWrapper);
        Ivar edgeIvar = class_getInstanceVariable(edgeCls, "_edge");
        if (!edgeIvar) return nil;
        return object_getIvar(feedEdgeWrapper, edgeIvar);
    } @catch (...) { return nil; }
}

static BOOL isAdEdge(id memEdge) {
    if (!memEdge) return NO;
    @try {
        SEL catSel = sel_registerName("category");
        if ([memEdge respondsToSelector:catSel]) {
            id cat = [memEdge performSelector:catSel];
            if ([cat isKindOfClass:[NSString class]]) {
                NSString *cs = (NSString *)cat;
                if ([cs isEqualToString:@"SPONSORED"] ||
                    [cs isEqualToString:@"AD"] ||
                    [cs isEqualToString:@"IN_STREAM_AD"]) {
                    return YES;
                }
            }
        }
    } @catch (...) {}
    return NO;
}

// ─── Hook 1: cellForItem — hide ad cells, use clear background ───
static IMP orig_cellForItem = NULL;
static int ad_hidden = 0;
static int cell_calls = 0;

static id hooked_cellForItem(id self, SEL _cmd, UICollectionView *cv, NSIndexPath *ip) {
    id result = nil;
    if (orig_cellForItem) {
        typedef id (*FnType)(id, SEL, id, id);
        FnType fn = (FnType)(uintptr_t)orig_cellForItem;
        result = fn(self, _cmd, (id)cv, (id)ip);
    }
    cell_calls++;
    if (!result || !ip || ip.section <= 1) return result;
    @try {
        id memEdge = getMemEdge(self, ip);
        if (memEdge && isAdEdge(memEdge)) {
            ad_hidden++;
            if ([result isKindOfClass:[UIView class]]) {
                UIView *v = (UIView *)result;
                v.hidden = YES;
                v.alpha = 0;
                v.backgroundColor = [UIColor clearColor];
                // Also try to make 0 frame
                v.frame = CGRectZero;
                v.bounds = CGRectZero;
                for (UIView *sub in v.subviews) {
                    sub.hidden = YES;
                }
            }
            if (ad_hidden <= 3 || (ad_hidden % 20) == 0) {
                LOG("[ad] hidden [%ld,%ld] total=%d\n", (long)ip.section, (long)ip.row, ad_hidden);
            }
        }
    } @catch (...) {}
    return result;
}

// ─── Hook 1b: willDisplayCell — backup ───
static IMP orig_willDisplay = NULL;

static void hooked_willDisplay(id self, SEL _cmd, UICollectionView *cv, UICollectionViewCell *cell, NSIndexPath *ip) {
    if (orig_willDisplay) {
        typedef void (*FnType)(id, SEL, id, id, id);
        FnType fn = (FnType)(uintptr_t)orig_willDisplay;
        fn(self, _cmd, (id)cv, (id)cell, (id)ip);
    }
    if (!cell || !ip || ip.section <= 1) return;
    UIView *v = [cell isKindOfClass:[UIView class]] ? (UIView *)cell : nil;
    if (!v) return;
    @try {
        id memEdge = getMemEdge(self, ip);
        if (memEdge && isAdEdge(memEdge)) {
            v.hidden = YES;
            v.alpha = 0;
            v.frame = CGRectZero;
            v.bounds = CGRectZero;
        }
    } @catch (...) {}
}

// ─── Hook 2-4: Story seen - block 3 paths ───
static int seen_count = 0;
static IMP orig_seen1 = NULL, orig_seen2 = NULL, orig_seen3 = NULL;

static void noop_seen_1(id self, SEL _cmd, id a, id b) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked _sendSeenThreadIDsWithBucket (count=%d)\n", seen_count);
    }
}
static void noop_seen_2(id self, SEL _cmd, id a) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked _sendThreadIDsAsSeenInViewerSession (count=%d)\n", seen_count);
    }
}
static void noop_seen_3(id self, SEL _cmd, id a, id b, id c, BOOL d, id e, id f) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked markThreadsView (count=%d)\n", seen_count);
    }
}

// ─── Install ───
static IMP orig_viewDidAppear = NULL;
static int setupDone = 0;

static void installHooks(void) {
    if (setupDone) return;
    setupDone = 1;
    LOG("\n=== Installing hooks (R3.5/v7) ===\n");

    @try {
        // Hook 0: FBMemNewsFeedEdge.node - return nil for SPONSORED
        Class memEdgeCls = objc_getClass("FBMemNewsFeedEdge");
        if (memEdgeCls) {
            SEL nodeSel = sel_registerName("node");
            Method m = class_getInstanceMethod(memEdgeCls, nodeSel);
            if (m) {
                orig_node = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_node);
                LOG("  hook #0: FBMemNewsFeedEdge.node -> nil for SPONSORED\n");
            } else {
                LOG("  FBMemNewsFeedEdge.node NOT FOUND\n");
            }
        } else {
            LOG("  FBMemNewsFeedEdge class NOT FOUND\n");
        }

        // Hook 1-2: FBComponentCollectionViewDataSource
        Class dsCls = objc_getClass("FBComponentCollectionViewDataSource");
        if (dsCls) {
            Method m1 = class_getInstanceMethod(dsCls, @selector(collectionView:cellForItemAtIndexPath:));
            if (m1) {
                orig_cellForItem = method_getImplementation(m1);
                method_setImplementation(m1, (IMP)hooked_cellForItem);
                LOG("  hook #1: cellForItem\n");
            }
            Method m2 = class_getInstanceMethod(dsCls, @selector(collectionView:willDisplayCell:forItemAtIndexPath:));
            if (m2) {
                orig_willDisplay = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)hooked_willDisplay);
                LOG("  hook #2: willDisplay\n");
            }
        }

        // Hook 3-5: Story seen - block 3 paths
        Class seenCls = objc_getClass("FBSnacksBucketsSeenStateManager");
        if (seenCls) {
            SEL sel1 = sel_registerName("_sendSeenThreadIDsWithBucket:session:");
            Method m1 = class_getInstanceMethod(seenCls, sel1);
            if (m1) {
                orig_seen1 = method_getImplementation(m1);
                method_setImplementation(m1, (IMP)noop_seen_1);
                LOG("  hook #3: _sendSeenThreadIDsWithBucket:session: -> no-op\n");
            }
            SEL sel2 = sel_registerName("_sendThreadIDsAsSeenInViewerSession:");
            Method m2 = class_getInstanceMethod(seenCls, sel2);
            if (m2) {
                orig_seen2 = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)noop_seen_2);
                LOG("  hook #4: _sendThreadIDsAsSeenInViewerSession: -> no-op\n");
            }
            SEL sel3 = sel_registerName("markThreadsViewReceiptsAndLightweightReactionsAsSeen:bucket:session:isHighlight:successBlock:noThreadsToMarkAsSeenBlock:");
            Method m3 = class_getInstanceMethod(seenCls, sel3);
            if (m3) {
                orig_seen3 = method_getImplementation(m3);
                method_setImplementation(m3, (IMP)noop_seen_3);
                LOG("  hook #5: markThreadsView... -> no-op\n");
            }
        }

        LOG("=== Done ===\n");
    } @catch (NSException *e) {
        LOG("  EXC: %s\n", e.reason.UTF8String);
    } @catch (...) {
        LOG("  EXC(c++)\n");
    }
}

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) {
        typedef void (*FnType)(id, SEL, BOOL);
        FnType fn = (FnType)(uintptr_t)orig_viewDidAppear;
        fn(self, _cmd, animated);
    }
    if (setupDone) return;
    const char *cn = class_getName(object_getClass(self));
    if (cn && strstr(cn, "FBNewsFeedViewController")) {
        dispatch_async(dispatch_get_main_queue(), ^{ installHooks(); });
    }
}

__attribute__((constructor))
static void glow_init(void) {
    const char *home = getenv("HOME");
    if (home) snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow.txt", home);
    LOG("\n=== Glow R3.5/v7 — %s ===\n", __DATE__ " " __TIME__);
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class vcClass = objc_getClass("UIViewController");
            if (vcClass) {
                Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
                if (m) {
                    orig_viewDidAppear = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_viewDidAppear);
                    LOG("[ctor] viewDidAppear hook installed\n");
                }
            }
        } @catch (...) {}
    });
}

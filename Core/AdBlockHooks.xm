// AdBlockHooks.xm
// Hooks for blocking ads in NewsFeed
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

// ═══════════════════════════════════════════════════════════════
// SECTION 3: Ad blocking - hook FBMemNewsFeedEdge.node
// ═══════════════════════════════════════════════════════════════

static IMP orig_node = NULL;
static id hooked_node(id self, SEL _cmd) {
    id orig = orig_node ? ((id(*)(id, SEL))orig_node)(self, _cmd) : nil;
    @try {
        id category = [orig category];
        if (category && ![category isEqualToString:@"ORGANIC"]) {
            return nil;
        }
    } @catch (NSException *e) {}
    return orig;
}

static IMP orig_cellForItem = NULL;
static id hooked_cellForItem(id self, SEL _cmd, UICollectionView *cv, NSIndexPath *ip) {
    return orig_cellForItem ? ((id(*)(id, SEL, id, id))orig_cellForItem)(self, _cmd, cv, ip) : nil;
}

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
        // Get memEdge from data source
        SEL memEdgeSel = sel_registerName("dataSourceState");
        id dataSourceState = [self respondsToSelector:memEdgeSel] ? [self performSelector:memEdgeSel] : nil;
        // Check if sponsored via category check
        // Simplified - just hide if not in section 0 or 1
    } @catch (...) {}
}

void initAdBlockHooks(void) {
    @try {
        // Hook 0: FBMemNewsFeedEdge.node
        if ([GlowSettingsManager shared].removeAds) {
            Class memEdgeCls = objc_getClass("FBMemNewsFeedEdge");
            if (memEdgeCls) {
                SEL nodeSel = sel_registerName("node");
                Method m = class_getInstanceMethod(memEdgeCls, nodeSel);
                if (m) {
                    orig_node = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_node);
                    LOG("  hook #0: FBMemNewsFeedEdge.node -> nil for SPONSORED\n");
                }
            }
        }

        // Hook 1-2: cellForItem, willDisplay
        if ([GlowSettingsManager shared].removeAds) {
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
        }
    } @catch (NSException *e) {
        LOG("[dl/adblock] init exc: %s\n", e.reason.UTF8String);
    }
}

// StorySeenHooks.xm
// Hooks for blocking story seen receipts
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

static int seen_count = 0;
static IMP orig_seen1 = NULL, orig_seen2 = NULL, orig_seen3 = NULL;

static id noop_seen_1(id self, SEL _cmd, id a, id b) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] blocked _sendSeenThreadIDsWithBucket (count=%d)\n", seen_count);
    }
    // Block network seen request - DO NOT call original IMP
    return nil;
}

static id noop_seen_2(id self, SEL _cmd, id a) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] local seen _sendThreadIDsAsSeenInViewerSession (count=%d)\n", seen_count);
    }
    // Call original to update local UI/state
    if (orig_seen2) {
        typedef id (*Fn)(id, SEL, id);
        return ((Fn)orig_seen2)(self, _cmd, a);
    }
    return nil;
}

static id noop_seen_3(id self, SEL _cmd, id a, id b, id c, BOOL d, id e, id f) {
    seen_count++;
    if (seen_count <= 5 || (seen_count % 50) == 0) {
        LOG("[seen] local seen markThreadsViewReceiptsAndLightweightReactionsAsSeen (count=%d)\n", seen_count);
    }
    // Call original to update local UI/state
    if (orig_seen3) {
        typedef id (*Fn)(id, SEL, id, id, id, BOOL, id, id);
        return ((Fn)orig_seen3)(self, _cmd, a, b, c, d, e, f);
    }
    return nil;
}

void initStorySeenHooks(void) {
    if (![GlowSettingsManager shared].disableStorySeen) return;
    @try {
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
                LOG("  hook #5: markThreadsViewReceipts...AsSeen -> no-op\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/seen] init exc: %s\n", e.reason.UTF8String);
    }
}

// ReelsDownloadHooks.xm
// Hooks for Reels download (FBShortsSideBarView)
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowReelHandler.h"
#import "GlowCommon.h"

static IMP orig_shortsSideBarDidMoveToWindow = NULL;
static IMP orig_shortsSideBarLayoutSubviews = NULL;

static void hooked_shortsSideBarDidMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_shortsSideBarDidMoveToWindow) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_shortsSideBarDidMoveToWindow)(self, _cmd, (id)window);
    }
    if (![GlowSettingsManager shared].downloadReels) return;
    if (!window) return;

    UIView *sideBar = (UIView *)self;
    @try {
        // Add download button
        [[GlowReelHandler shared] addDownloadButtonToSidebar:sideBar];
        // Pre-warm URLs
        [[GlowReelHandler shared] preWarmURLsForSidebar:sideBar];
    } @catch (NSException *e) {
        LOG("[reels/main] didMoveToWindow exc: %s\n", e.reason.UTF8String);
    }
}

static void hooked_shortsSideBarLayoutSubviews(id self, SEL _cmd) {
    if (orig_shortsSideBarLayoutSubviews) {
        typedef void (*FnType)(id, SEL);
        ((FnType)orig_shortsSideBarLayoutSubviews)(self, _cmd);
    }
    if (![GlowSettingsManager shared].downloadReels) return;

    UIView *sideBar = (UIView *)self;
    @try {
        // Fallback: also add in layoutSubviews
        [[GlowReelHandler shared] addDownloadButtonToSidebar:sideBar];
    } @catch (NSException *e) {
        LOG("[reels/main] layoutSubviews exc: %s\n", e.reason.UTF8String);
    }
}

void initReelsDownloadHooks(void) {
    if (![GlowSettingsManager shared].downloadReels) return;
    @try {
        Class sideBarCls = objc_getClass("FBShortsSideBarView");
        if (sideBarCls) {
            // Primary: didMoveToWindow (better timing)
            SEL dmwSel = @selector(didMoveToWindow);
            Method dmwM = class_getInstanceMethod(sideBarCls, dmwSel);
            if (dmwM) {
                orig_shortsSideBarDidMoveToWindow = method_getImplementation(dmwM);
                method_setImplementation(dmwM, (IMP)hooked_shortsSideBarDidMoveToWindow);
                LOG("  hook #11a: FBShortsSideBarView.didMoveToWindow -> add download button\n");
            }

            // Fallback: layoutSubviews
            SEL lsSel = @selector(layoutSubviews);
            Method lsM = class_getInstanceMethod(sideBarCls, lsSel);
            if (lsM) {
                orig_shortsSideBarLayoutSubviews = method_getImplementation(lsM);
                method_setImplementation(lsM, (IMP)hooked_shortsSideBarLayoutSubviews);
                LOG("  hook #11b: FBShortsSideBarView.layoutSubviews -> fallback\n");
            }
        } else {
            LOG("  FBShortsSideBarView NOT FOUND (will retry when Reels opens)\n");
        }
    } @catch (NSException *e) {
        LOG("[dl/reels] init exc: %s\n", e.reason.UTF8String);
    }
}

// VideoItemHooks.xm
// Hooks to capture video URLs (HD/SD) from FBVideoPlaybackItem
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowLogManager.h"

static IMP orig_HDPlaybackURL = NULL;
static IMP orig_SDPlaybackURL = NULL;

static NSURL *hooked_HDPlaybackURL(id self, SEL _cmd) {
    NSURL *url = nil;
    if (orig_HDPlaybackURL) {
        typedef NSURL *(*FnType)(id, SEL);
        url = ((FnType)orig_HDPlaybackURL)(self, _cmd);
    }
    if (url && self) {
        [[GlowCacheManager shared] setCachedHDURL:url];
        [[GlowCacheManager shared] setURLsForItem:self hd:url sd:nil];
        LOG("[dl/reel] CAPTURED HD: %s\n", [[url absoluteString] UTF8String]);
    }
    return url;
}

static NSURL *hooked_SDPlaybackURL(id self, SEL _cmd) {
    NSURL *url = nil;
    if (orig_SDPlaybackURL) {
        typedef NSURL *(*FnType)(id, SEL);
        url = ((FnType)orig_SDPlaybackURL)(self, _cmd);
    }
    if (url && self) {
        [[GlowCacheManager shared] setCachedSDURL:url];
        [[GlowCacheManager shared] setURLsForItem:self hd:nil sd:url];
        LOG("[dl/reel] CAPTURED SD: %s\n", [[url absoluteString] UTF8String]);
    }
    return url;
}

void initVideoItemHooks(void) {
    if (![GlowSettingsManager shared].downloadVideo) return;
    @try {
        Class vpiCls = objc_getClass("FBVideoPlaybackItem");
        if (vpiCls) {
            SEL hdSel = sel_registerName("HDPlaybackURL");
            Method hdM = class_getInstanceMethod(vpiCls, hdSel);
            if (hdM) {
                orig_HDPlaybackURL = method_getImplementation(hdM);
                method_setImplementation(hdM, (IMP)hooked_HDPlaybackURL);
                LOG("  hook #12a: FBVideoPlaybackItem.HDPlaybackURL -> capture URL\n");
            }
            SEL sdSel = sel_registerName("SDPlaybackURL");
            Method sdM = class_getInstanceMethod(vpiCls, sdSel);
            if (sdM) {
                orig_SDPlaybackURL = method_getImplementation(sdM);
                method_setImplementation(sdM, (IMP)hooked_SDPlaybackURL);
                LOG("  hook #12b: FBVideoPlaybackItem.SDPlaybackURL -> capture URL\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/videoitem] init exc: %s\n", e.reason.UTF8String);
    }
}

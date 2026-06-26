// PlaybackStateHooks.xm - STUB
// Hooks for tracking active playback state (setPlayingVideo:, setPlayingRequested:)
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowLogManager.h"

static IMP orig_setPlayingVideo = NULL;
static IMP orig_setPlayingRequested = NULL;

static void hooked_setPlayingVideo(id self, SEL _cmd, BOOL playing) {
    if (orig_setPlayingVideo) {
        typedef void (*FnType)(id, SEL, BOOL);
        ((FnType)orig_setPlayingVideo)(self, _cmd, playing);
    }
    if (playing && self) {
        SEL itemSel = sel_registerName("currentVideoPlaybackItem");
        if ([self respondsToSelector:itemSel]) {
            id liveItem = [self performSelector:itemSel];
            if (liveItem) {
                [GlowCacheManager shared].currentPlayingItem = liveItem;
                LOG("[Glow/Engine] Screen focus shifted (setPlayingVideo:). item=%s ptr=%p\n",
                    class_getName(object_getClass(liveItem)), liveItem);
            }
        }
    }
}

static void hooked_setPlayingRequested(id self, SEL _cmd, BOOL playing) {
    if (orig_setPlayingRequested) {
        typedef void (*FnType)(id, SEL, BOOL);
        ((FnType)orig_setPlayingRequested)(self, _cmd, playing);
    }
    if (playing && self) {
        SEL itemSel = sel_registerName("currentVideoPlaybackItem");
        if ([self respondsToSelector:itemSel]) {
            id liveItem = [self performSelector:itemSel];
            if (liveItem) {
                [GlowCacheManager shared].currentPlayingItem = liveItem;
                LOG("[Glow/Engine] Screen focus shifted (setPlayingRequested:). item=%s ptr=%p\n",
                    class_getName(object_getClass(liveItem)), liveItem);
            }
        }
    }
}

void initPlaybackStateHooks(void) {
    if (![GlowSettingsManager shared].downloadReels) return;
    @try {
        // Hook on FBVideoPlaybackController only
        Class vpcCls = NSClassFromString(@"FBVideoPlaybackController");
        if (!vpcCls) return;

        SEL sel1 = sel_registerName("setPlayingVideo:");
        if (class_respondsToSelector(vpcCls, sel1)) {
            Method m = class_getInstanceMethod(vpcCls, sel1);
            if (m) {
                orig_setPlayingVideo = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_setPlayingVideo);
                LOG("  hook: setPlayingVideo: on FBVideoPlaybackController\n");
            }
        }
        SEL sel2 = sel_registerName("setPlayingRequested:");
        if (class_respondsToSelector(vpcCls, sel2)) {
            Method m = class_getInstanceMethod(vpcCls, sel2);
            if (m) {
                orig_setPlayingRequested = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_setPlayingRequested);
                LOG("  hook: setPlayingRequested: on FBVideoPlaybackController\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/playback] init exc: %s\n", e.reason.UTF8String);
    }
}

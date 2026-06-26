// RuntimeEnumHooks.xm
// Runtime class enumeration - finds FB classes dynamically
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowCommon.h"

// Runtime enum state
static int g_glowStyleInstalled = 0;
static int setVideoItemHooked = 0;
static int cvpiHooked = 0;
static int setPlayerHooked = 0;
static int setPlayCtrlHooked = 0;
static int cfgVideoHooked = 0;
static int cfgModelHooked = 0;
static int setPlayingVideoHooked = 0;
static int setPlayingRequestedHooked = 0;

static IMP orig_setVideoItem = NULL;
static IMP orig_currentVideoPlaybackItem = NULL;
static IMP orig_setVideoPlayer = NULL;
static IMP orig_setPlaybackController = NULL;
static IMP orig_configureWithVideo = NULL;
static IMP orig_configureWithModel = NULL;
static IMP orig_setPlayingVideo = NULL;
static IMP orig_setPlayingRequested = NULL;

static void hooked_setVideoItem(id self, SEL _cmd, id newItem) {
    if (orig_setVideoItem) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_setVideoItem)(self, _cmd, newItem);
    }
}

static id hooked_currentVideoPlaybackItem(id self, SEL _cmd) {
    return orig_currentVideoPlaybackItem ?
        ((id(*)(id, SEL))orig_currentVideoPlaybackItem)(self, _cmd) : nil;
}

static void hooked_setVideoPlayer(id self, SEL _cmd, id player) {
    if (orig_setVideoPlayer) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_setVideoPlayer)(self, _cmd, player);
    }
}

static void hooked_setPlaybackController(id self, SEL _cmd, id ctrl) {
    if (orig_setPlaybackController) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_setPlaybackController)(self, _cmd, ctrl);
    }
}

static void hooked_configureWithVideo(id self, SEL _cmd, id video) {
    if (orig_configureWithVideo) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_configureWithVideo)(self, _cmd, video);
    }
}

static void hooked_configureWithModel(id self, SEL _cmd, id model) {
    if (orig_configureWithModel) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_configureWithModel)(self, _cmd, model);
    }
}

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
                LOG("[Glow/Engine] Screen focus shifted (setPlayingVideo:). item=%s\n",
                    class_getName(object_getClass(liveItem)));
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
                LOG("[Glow/Engine] Screen focus shifted (setPlayingRequested:). item=%s\n",
                    class_getName(object_getClass(liveItem)));
            }
        }
    }
}

void initRuntimeEnumHooks(void) {
    if (g_glowStyleInstalled) return;
    g_glowStyleInstalled = 1;

    @try {
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) return;

        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * count);
        objc_getClassList(classes, count);

        SEL setSel = sel_registerName("setVideoItem:");
        SEL getSel = sel_registerName("currentVideoPlaybackItem");
        SEL setPlayerSel = sel_registerName("setVideoPlayer:");
        SEL setPlayCtrlSel = sel_registerName("setPlaybackController:");
        SEL cfgVideoSel = sel_registerName("configureWithVideo:");
        SEL cfgModelSel = sel_registerName("configureWithModel:");
        SEL setPlayingVideoSel = sel_registerName("setPlayingVideo:");
        SEL setPlayingRequestedSel = sel_registerName("setPlayingRequested:");

        for (int i = 0; i < count; i++) {
            Class cls = classes[i];
            if (!cls) continue;
            @try {
                const char *name = class_getName(cls);
                if (!name) continue;
                if (strncmp(name, "FB", 2) != 0 && strncmp(name, "FBS", 3) != 0) continue;

                // Hook setVideoItem:
                if (!orig_setVideoItem && class_respondsToSelector(cls, setSel)) {
                    Method m = class_getInstanceMethod(cls, setSel);
                    if (m) {
                        orig_setVideoItem = method_getImplementation(m);
                        method_setImplementation(m, (IMP)hooked_setVideoItem);
                        setVideoItemHooked++;
                    }
                }

                // Hook currentVideoPlaybackItem
                if (!orig_currentVideoPlaybackItem && class_respondsToSelector(cls, getSel)) {
                    Method m = class_getInstanceMethod(cls, getSel);
                    if (m) {
                        orig_currentVideoPlaybackItem = method_getImplementation(m);
                        method_setImplementation(m, (IMP)hooked_currentVideoPlaybackItem);
                        cvpiHooked++;
                    }
                }

                // Hook setPlayingVideo: on FBVideoPlaybackController only
                if (!orig_setPlayingVideo && strstr(name, "FBVideoPlaybackController") != NULL) {
                    if (class_respondsToSelector(cls, setPlayingVideoSel)) {
                        Method m = class_getInstanceMethod(cls, setPlayingVideoSel);
                        if (m) {
                            orig_setPlayingVideo = method_getImplementation(m);
                            method_setImplementation(m, (IMP)hooked_setPlayingVideo);
                            setPlayingVideoHooked++;
                            LOG("[dl/reel] hooked setPlayingVideo: on %s\n", name);
                        }
                    }
                }

                // Hook setPlayingRequested: on FBVideoPlaybackController only
                if (!orig_setPlayingRequested && strstr(name, "FBVideoPlaybackController") != NULL) {
                    if (class_respondsToSelector(cls, setPlayingRequestedSel)) {
                        Method m = class_getInstanceMethod(cls, setPlayingRequestedSel);
                        if (m) {
                            orig_setPlayingRequested = method_getImplementation(m);
                            method_setImplementation(m, (IMP)hooked_setPlayingRequested);
                            setPlayingRequestedHooked++;
                            LOG("[dl/reel] hooked setPlayingRequested: on %s\n", name);
                        }
                    }
                }

                // Hook setVideoPlayer:, setPlaybackController:
                if (class_respondsToSelector(cls, setPlayerSel)) {
                    Method m = class_getInstanceMethod(cls, setPlayerSel);
                    if (m) {
                        if (!orig_setVideoPlayer) {
                            orig_setVideoPlayer = method_getImplementation(m);
                        }
                        method_setImplementation(m, (IMP)hooked_setVideoPlayer);
                        setPlayerHooked++;
                    }
                }
                if (class_respondsToSelector(cls, setPlayCtrlSel)) {
                    Method m = class_getInstanceMethod(cls, setPlayCtrlSel);
                    if (m) {
                        if (!orig_setPlaybackController) {
                            orig_setPlaybackController = method_getImplementation(m);
                        }
                        method_setImplementation(m, (IMP)hooked_setPlaybackController);
                        setPlayCtrlHooked++;
                    }
                }

                // Hook configureWithVideo:, configureWithModel:
                if (class_respondsToSelector(cls, cfgVideoSel)) {
                    Method m = class_getInstanceMethod(cls, cfgVideoSel);
                    if (m) {
                        if (!orig_configureWithVideo) {
                            orig_configureWithVideo = method_getImplementation(m);
                        }
                        method_setImplementation(m, (IMP)hooked_configureWithVideo);
                        cfgVideoHooked++;
                    }
                }
                if (class_respondsToSelector(cls, cfgModelSel)) {
                    Method m = class_getInstanceMethod(cls, cfgModelSel);
                    if (m) {
                        if (!orig_configureWithModel) {
                            orig_configureWithModel = method_getImplementation(m);
                        }
                        method_setImplementation(m, (IMP)hooked_configureWithModel);
                        cfgModelHooked++;
                    }
                }
            } @catch (NSException *ex) {
                // Skip bad classes (FBGraphQLQueryBuilder, etc)
                continue;
            }
        }
        free(classes);

        LOG("[dl/reel] RuntimeEnumHooks installed: setVideoItem=%d cvpi=%d setPlayer=%d setPlayCtrl=%d cfgVideo=%d cfgModel=%d setPlayingVideo=%d setPlayingRequested=%d\n",
            setVideoItemHooked, cvpiHooked, setPlayerHooked, setPlayCtrlHooked,
            cfgVideoHooked, cfgModelHooked, setPlayingVideoHooked, setPlayingRequestedHooked);
    } @catch (NSException *e) {
        LOG("[dl/runtime] init exc: %s\n", e.reason.UTF8String);
    }
}

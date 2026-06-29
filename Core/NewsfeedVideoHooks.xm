// NewsfeedVideoHooks.xm
// Hooks for newsfeed video download (FBVideoPlaybackContainerView long press)
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowVideoHandler.h"
#import "GlowCommon.h"

static Class g_videoContainerClass = nil;
static BOOL g_videoContainerSearched = NO;
static const void *kGlowVideoContainerLPKey = &kGlowVideoContainerLPKey;
static IMP orig_videoContainerDidMoveToWindow = NULL;

static Class findVideoContainerClass(void) {
    if (g_videoContainerSearched) return g_videoContainerClass;
    g_videoContainerSearched = YES;

    const char *candidates[] = {
        "FBVideoPlaybackContainerView",  // FB 560.x
        "FBVideoContainerView",
        "FBFeedVideoContainerView",
        "FBNewsFeedVideoContainerView"
    };

    for (int i = 0; i < sizeof(candidates)/sizeof(candidates[0]); i++) {
        Class cls = objc_getClass(candidates[i]);
        if (cls) {
            g_videoContainerClass = cls;
            LOG("[dl/news] Found VideoContainer class: %s\n", candidates[i]);
            return cls;
        }
    }
    LOG("[dl/news] VideoContainerView NOT FOUND in 560.x\n");
    return nil;
}

static void hooked_videoContainerDidMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_videoContainerDidMoveToWindow) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_videoContainerDidMoveToWindow)(self, _cmd, (id)window);
    }
    
    // CRITICAL: Only apply to instances of the actual video container class to prevent generic UIView hooking
    if (![self isKindOfClass:g_videoContainerClass]) return;
    if (!window) return;

    // Check if in Reels context (walk responder chain)
    UIResponder *r = (UIResponder *)self;
    BOOL isReel = NO;
    while (r) {
        const char *name = class_getName(object_getClass(r));
        if (name && (strstr(name, "Shorts") != NULL || strstr(name, "Reel") != NULL)) {
            isReel = YES;
            break;
        }
        r = [r nextResponder];
    }
    
    if (isReel) {
        // Skip adding long press to video container in Reels context
        return;
    }

    // Add long press gesture using static key
    NSNumber *already = objc_getAssociatedObject(self, kGlowVideoContainerLPKey);
    if (!already) {
        objc_setAssociatedObject(self, kGlowVideoContainerLPKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:[GlowVideoHandler shared]
                    action:@selector(onVideoContainerLongPress:)];
        lp.minimumPressDuration = 0.5;
        [(UIView *)self addGestureRecognizer:lp];
        LOG("[dl/news] Added long press gesture to newsfeed video container\n");
    }
}

void initNewsfeedVideoHooks(void) {
    if (![GlowSettingsManager shared].downloadVideo) return;
    @try {
        Class cls = findVideoContainerClass();
        if (cls) {
            SEL dmwSel = @selector(didMoveToWindow);
            Method dmwM = class_getInstanceMethod(cls, dmwSel);
            if (dmwM) {
                orig_videoContainerDidMoveToWindow = method_getImplementation(dmwM);
                method_setImplementation(dmwM, (IMP)hooked_videoContainerDidMoveToWindow);
                LOG("  hook #9b: %s.didMoveToWindow -> add long press if in newsfeed\n", class_getName(cls));
            }
        } else {
            LOG("  hook #9: NewsfeedVideoHooks SKIPPED (no container class)\n");
        }
    } @catch (NSException *e) {
        LOG("[dl/news] init exc: %s\n", e.reason.UTF8String);
    }
}

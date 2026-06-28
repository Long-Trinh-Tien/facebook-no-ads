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

static Class findVideoContainerClass(void) {
    if (g_videoContainerSearched) return g_videoContainerClass;
    g_videoContainerSearched = YES;

    // Do NOT include generic "VideoContainerView" which subclasses UITabBarItem views
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

void initNewsfeedVideoHooks(void) {
    if (![GlowSettingsManager shared].downloadVideo) return;
    @try {
        Class cls = findVideoContainerClass();
        if (cls) {
            SEL initSel = @selector(initWithFrame:);
            Method initM = class_getInstanceMethod(cls, initSel);
            if (initM) {
                IMP origInit = method_getImplementation(initM);
                method_setImplementation(initM, imp_implementationWithBlock(^(id self, CGRect frame) {
                    id result = ((id(*)(id, SEL, CGRect))origInit)(self, initSel, frame);

                    // Add long press gesture using static key
                    NSNumber *already = objc_getAssociatedObject(self, kGlowVideoContainerLPKey);
                    if (!already) {
                        objc_setAssociatedObject(self, kGlowVideoContainerLPKey, @YES,
                                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                            initWithTarget:[GlowVideoHandler shared]
                                    action:@selector(onVideoContainerLongPress:)];
                        lp.minimumPressDuration = 0.5;
                        [self addGestureRecognizer:lp];
                    }
                    return result;
                }));
                LOG("  hook #9b: %s.initWithFrame: -> add long press\n", class_getName(cls));
            }
        } else {
            LOG("  hook #9: NewsfeedVideoHooks SKIPPED (no container class)\n");
        }
    } @catch (NSException *e) {
        LOG("[dl/news] init exc: %s\n", e.reason.UTF8String);
    }
}

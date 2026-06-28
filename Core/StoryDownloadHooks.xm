// StoryDownloadHooks.xm
// Hooks for Story download (FBSnacksMediaContainerView)
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowStoryHandler.h"
#import "GlowViewUtils.h"

static IMP orig_storyContainer_init = NULL;
static IMP orig_storyContainer_didMoveToWindow = NULL;
static NSMutableSet *g_storyContainersWithButton = nil;

static id hooked_storyContainer_init(id self, SEL _cmd, id thread, id bucket, id mediaViewDelegate, id mediaViewGenerator, id toolbox, BOOL shouldBlurMedia) {
    if (orig_storyContainer_init) {
        typedef id (*FnType)(id, SEL, id, id, id, id, id, BOOL);
        return ((FnType)orig_storyContainer_init)(self, _cmd, thread, bucket,
                                                   mediaViewDelegate, mediaViewGenerator,
                                                   toolbox, shouldBlurMedia);
    }
    return self;
}

static void hooked_storyContainer_didMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_storyContainer_didMoveToWindow) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_storyContainer_didMoveToWindow)(self, _cmd, (id)window);
    }
    if (![GlowSettingsManager shared].downloadStory) return;
    if (!window) return;

    if (!g_storyContainersWithButton) {
        g_storyContainersWithButton = [[NSMutableSet alloc] init];
    }

    @try {
        NSValue *key = [NSValue valueWithNonretainedObject:self];
        if ([g_storyContainersWithButton containsObject:key]) return;

        UIWindow *keyWindow = [GlowViewUtils keyWindow];
        if (!keyWindow) {
            LOG("[dl/story] keyWindow is nil, cannot add button\n");
            return;
        }

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120, 44, 44);
        [btn setImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        btn.layer.cornerRadius = 22;
        btn.clipsToBounds = YES;
        btn.layer.zPosition = 9999;
        [btn addTarget:[GlowStoryHandler shared] action:@selector(onStoryDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        UIView *container = (UIView *)self;
        [container addSubview:btn];
        [container bringSubviewToFront:btn];

        [g_storyContainersWithButton addObject:key];
        LOG("[dl/story] added download BUTTON to container %p at (%.0f, %.0f)\n",
            self, keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120);
    } @catch (NSException *e) {
        LOG("[dl/story] didMoveToWindow exc: %s\n", e.reason.UTF8String);
    }
}

void initStoryDownloadHooks(void) {
    if (![GlowSettingsManager shared].downloadStory) return;
    @try {
        Class cls = objc_getClass("FBSnacksMediaContainerView");
        if (cls) {
            SEL sel = sel_registerName("initWithThread:bucket:mediaViewDelegate:mediaViewGenerator:toolbox:shouldBlurMedia:");
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                orig_storyContainer_init = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_storyContainer_init);
                LOG("  hook #8: FBSnacksMediaContainerView init (passive)\n");
            }

            SEL dmwSel = @selector(didMoveToWindow);
            Method dmwM = class_getInstanceMethod(cls, dmwSel);
            if (dmwM) {
                orig_storyContainer_didMoveToWindow = method_getImplementation(dmwM);
                method_setImplementation(dmwM, (IMP)hooked_storyContainer_didMoveToWindow);
                LOG("  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add button\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/story] init exc: %s\n", e.reason.UTF8String);
    }
}

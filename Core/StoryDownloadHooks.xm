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
static const void *kGlowStoryContainerLPKey = &kGlowStoryContainerLPKey;

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

    @try {
        UIView *container = (UIView *)self;
        // Check if gesture already added using static key
        NSNumber *already = objc_getAssociatedObject(container, kGlowStoryContainerLPKey);
        if (already && [already boolValue]) {
            return;
        }

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:[GlowStoryHandler shared]
            action:@selector(onStoryLongPress:)];
        lp.minimumPressDuration = 0.5;
        [container addGestureRecognizer:lp];

        objc_setAssociatedObject(container, kGlowStoryContainerLPKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LOG("[dl/story] added long press gesture to story container %p\n", container);
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
                LOG("  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add long press\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/story] init exc: %s\n", e.reason.UTF8String);
    }
}

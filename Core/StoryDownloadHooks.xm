// StoryDownloadHooks.xm
// Hooks for Story download (FBSnacksMediaContainerView) with correct didMoveToWindow signature
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowStoryHandler.h"
#import "GlowViewUtils.h"

static IMP orig_storyContainer_didMoveToWindow = NULL;
static const void *kGlowStoryContainerLPKey = &kGlowStoryContainerLPKey;

// didMoveToWindow takes no arguments in UIKit, matching the signature exactly to avoid ARM64 stack corruption
static void hooked_storyContainer_didMoveToWindow(id self, SEL _cmd) {
    if (orig_storyContainer_didMoveToWindow) {
        typedef void (*FnType)(id, SEL);
        ((FnType)orig_storyContainer_didMoveToWindow)(self, _cmd);
    }
    
    // CRITICAL: Only apply to FBSnacksMediaContainerView instances to prevent generic UIView hooking
    if (![self isKindOfClass:objc_getClass("FBSnacksMediaContainerView")]) return;
    
    if (![GlowSettingsManager shared].downloadStory) return;
    
    UIView *container = (UIView *)self;
    UIWindow *window = container.window;
    if (!window) return;

    @try {
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

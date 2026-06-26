// StoryDownloadHooks.xm
// Hooks for story download (FBSnacksMediaContainerView)
// RESTORED from v8.2.64 (commit 31e2fbf) - was working perfectly
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"
#import "GlowViewUtils.h"
#import "GlowStoryHandler.h"

// Track which story containers already have button
static NSMutableSet *g_storyContainersWithButton = nil;

static IMP orig_storyContainer_init = NULL;

// v8.2.64: NOTE: Do NOT add gesture/button here - view is not laid out yet.
// Instead, hook didMoveToWindow below to add it when view is in window.
static id hooked_storyContainer_init(id self, SEL _cmd, id thread, id bucket,
                                     id mediaViewDelegate, id mediaViewGenerator,
                                     id toolbox, BOOL shouldBlurMedia) {
    id result = nil;
    if (orig_storyContainer_init) {
        typedef id (*FnType)(id, SEL, id, id, id, id, id, BOOL);
        result = ((FnType)orig_storyContainer_init)(self, _cmd, thread, bucket,
                                                    mediaViewDelegate, mediaViewGenerator,
                                                    toolbox, shouldBlurMedia);
    }
    return result;
}

static IMP orig_storyContainer_didMoveToWindow = NULL;

static void hooked_storyContainer_didMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_storyContainer_didMoveToWindow) {
        typedef void (*FnType)(id, SEL, id);
        ((FnType)orig_storyContainer_didMoveToWindow)(self, _cmd, (id)window);
    }
    if (![GlowSettingsManager shared].downloadStory) return;
    if (!window) return;  // removing from window
    if (!g_storyContainersWithButton) g_storyContainersWithButton = [[NSMutableSet alloc] init];
    if ([g_storyContainersWithButton containsObject:[NSValue valueWithNonretainedObject:self]]) return;

    @try {
        // Use keyWindow for positioning (window parameter can be unreliable)
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) {
                            keyWindow = w;
                            break;
                        }
                    }
                }
                if (keyWindow) break;
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
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
        btn.tag = 999888;  // marker to avoid duplicates
        [btn addTarget:[GlowStoryHandler shared] action:@selector(onStoryDownloadTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];

        [g_storyContainersWithButton addObject:[NSValue valueWithNonretainedObject:self]];
        LOG("[dl/story] added download BUTTON to container at (%.0f, %.0f)\n",
            keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120);
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
                LOG("  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add download button\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/story] init exc: %s\n", e.reason.UTF8String);
    }
}

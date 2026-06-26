// StoryDownloadHooks.xm
// Hooks for story download (FBSnacksMediaContainerView)
// FIX v8.3.1: Add long press gesture directly + improve media view lookup
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowStoryHandler.h"
#import "GlowLogManager.h"
#import "GlowViewUtils.h"

static IMP orig_storyContainer_init = NULL;

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

    // FIX v8.3.1: Add long press gesture directly in init (self-add approach)
    if (result && [GlowSettingsManager shared].downloadStory) {
        @try {
            // Check if already added (avoid duplicate)
            NSNumber *already = objc_getAssociatedObject(result, "GlowStoryLP");
            if (!already) {
                objc_setAssociatedObject(result, "GlowStoryLP", @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                    initWithTarget:[GlowStoryHandler shared]
                            action:@selector(onStoryLongPress:)];
                lp.minimumPressDuration = 0.5;
                lp.cancelsTouchesInView = NO;
                [(UIView *)result addGestureRecognizer:lp];

                LOG("[dl/story] Added long press to container %p\n", result);
            }
        } @catch (NSException *e) {
            LOG("[dl/story] init addLP exc: %s\n", e.reason.UTF8String);
        }
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
    if (!window) return;

    GlowCacheManager *cache = [GlowCacheManager shared];
    NSValue *key = [NSValue valueWithNonretainedObject:self];
    if ([cache.storyContainersWithLongPress containsObject:key]) return;

    @try {
        // Use keyWindow for positioning (window param can be unreliable)
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
                if (keyWindow) break;
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;

        // Also add long press as backup (in case init didn't add it)
        NSNumber *hasLP = objc_getAssociatedObject(self, "GlowStoryLP");
        if (!hasLP) {
            objc_setAssociatedObject(self, "GlowStoryLP", @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                initWithTarget:[GlowStoryHandler shared]
                        action:@selector(onStoryLongPress:)];
            lp.minimumPressDuration = 0.5;
            lp.cancelsTouchesInView = NO;
            [(UIView *)self addGestureRecognizer:lp];
        }

        // Add download button
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(keyWindow.frame.size.width - 60, keyWindow.frame.size.height - 120, 44, 44);
        [btn setImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        btn.layer.cornerRadius = 22;
        btn.clipsToBounds = YES;
        [btn addTarget:[GlowStoryHandler shared] action:@selector(onStoryDownloadTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];

        [cache.storyContainersWithLongPress addObject:key];
        LOG("[dl/story] added download BUTTON to container %p\n", self);
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
                LOG("  hook #8: FBSnacksMediaContainerView init -> add long press\n");
            } else {
                LOG("  FBSnacksMediaContainerView init NOT FOUND\n");
            }

            SEL dmwSel = @selector(didMoveToWindow);
            Method dmwM = class_getInstanceMethod(cls, dmwSel);
            if (dmwM) {
                orig_storyContainer_didMoveToWindow = method_getImplementation(dmwM);
                method_setImplementation(dmwM, (IMP)hooked_storyContainer_didMoveToWindow);
                LOG("  hook #8b: FBSnacksMediaContainerView didMoveToWindow -> add button\n");
            } else {
                LOG("  didMoveToWindow NOT FOUND\n");
            }
        } else {
            LOG("  FBSnacksMediaContainerView class NOT FOUND\n");
        }
    } @catch (NSException *e) {
        LOG("[dl/story] init exc: %s\n", e.reason.UTF8String);
    }
}

// Core/LongPressHooks.xm
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "UI/GlowSettingsViewController.h"
#import "Utils/GlowViewUtils.h"
#import "Utils/GlowCommon.h"

static IMP orig_tabbar_didMoveToWindow = NULL;

static void openGlowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            GlowSettingsViewController *vc = [[GlowSettingsViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            
            UIViewController *top = [GlowViewUtils topViewController];
            if (top) {
                [top presentViewController:nav animated:YES completion:^{
                    LOG("[ui] settings presented successfully\n");
                }];
            } else {
                LOG("[ui] failed to find top view controller to present settings\n");
            }
        } @catch (NSException *e) {
            LOG("[ui] settings presentation exc: %s\n", e.reason.UTF8String);
        }
    });
}

@interface GlowSettingsLongPressHandler : NSObject
@end

@implementation GlowSettingsLongPressHandler
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        LOG("[ui] tab bar long press triggered, opening settings\n");
        openGlowSettings();
    }
}
@end

static GlowSettingsLongPressHandler *g_lpHandler = nil;

static void hooked_tabbar_didMoveToWindow(id self, SEL _cmd, UIWindow *window) {
    if (orig_tabbar_didMoveToWindow) {
        typedef void (*Fn)(id, SEL, id);
        ((Fn)orig_tabbar_didMoveToWindow)(self, _cmd, (id)window);
    }
    if (!window) return;

    @try {
        UIView *tabBar = (UIView *)self;
        // Check if gesture already added using Associated Object
        NSNumber *already = objc_getAssociatedObject(tabBar, "GlowSettingsLP");
        if (already && [already boolValue]) {
            return;
        }

        if (!g_lpHandler) {
            g_lpHandler = [[GlowSettingsLongPressHandler alloc] init];
        }

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:g_lpHandler
            action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.8;
        lp.cancelsTouchesInView = NO;
        [tabBar addGestureRecognizer:lp];
        
        objc_setAssociatedObject(tabBar, "GlowSettingsLP", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LOG("[ui] added settings long press gesture to UITabBar\n");
    } @catch (NSException *e) {
        LOG("[ui] failed to add long press to UITabBar: %s\n", e.reason.UTF8String);
    }
}

void initLongPressHooks(void) {
    @try {
        Class cls = objc_getClass("UITabBar");
        if (cls) {
            SEL sel = @selector(didMoveToWindow);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                orig_tabbar_didMoveToWindow = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_tabbar_didMoveToWindow);
                LOG("  hook: UITabBar.didMoveToWindow -> add settings long press\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}

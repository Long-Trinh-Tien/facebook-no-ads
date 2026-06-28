// Core/LongPressHooks.xm
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "UI/GlowSettingsViewController.h"
#import "Utils/GlowViewUtils.h"
#import "Utils/GlowCommon.h"

static IMP orig_feed_viewDidAppear = NULL;

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
        LOG("[ui] long press triggered, opening settings\n");
        openGlowSettings();
    }
}
@end

static GlowSettingsLongPressHandler *g_lpHandler = nil;

static void hooked_feed_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_feed_viewDidAppear) {
        typedef void (*Fn)(id, SEL, BOOL);
        ((Fn)orig_feed_viewDidAppear)(self, _cmd, animated);
    }

    @try {
        UIViewController *vc = (UIViewController *)self;
        UIView *view = vc.view;
        if (view) {
            // Check if gesture already added using Associated Object
            NSNumber *already = objc_getAssociatedObject(view, "GlowSettingsLP");
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
            [view addGestureRecognizer:lp];
            
            objc_setAssociatedObject(view, "GlowSettingsLP", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            LOG("[ui] added long press gesture to FBNewsFeedViewController.view\n");
        }
    } @catch (NSException *e) {
        LOG("[ui] failed to add long press: %s\n", e.reason.UTF8String);
    }
}

void initLongPressHooks(void) {
    @try {
        Class cls = objc_getClass("FBNewsFeedViewController");
        if (cls) {
            SEL sel = @selector(viewDidAppear:);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                orig_feed_viewDidAppear = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_feed_viewDidAppear);
                LOG("  hook: FBNewsFeedViewController.viewDidAppear: -> add settings long press\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}

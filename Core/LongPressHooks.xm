// Core/LongPressHooks.xm
// Strict bottom Tab Bar icon long-press gesture attachment
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "UI/GlowSettingsViewController.h"
#import "Utils/GlowViewUtils.h"
#import "Utils/GlowCommon.h"

static const void *kGlowSettingsLPKey = &kGlowSettingsLPKey;
static BOOL g_isSettingsPresenting = NO;
BOOL g_tabBarGestureInstalled = NO;

static void openGlowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_isSettingsPresenting) return;
        
        UIViewController *top = [GlowViewUtils topViewController];
        if (!top) {
            LOG("[ui] failed to find top view controller to present settings\n");
            return;
        }
        
        // Prevent presentation if already presenting GlowSettingsViewController
        if ([top isKindOfClass:objc_getClass("GlowSettingsViewController")] ||
            ([top isKindOfClass:[UINavigationController class]] && 
             [((UINavigationController *)top).topViewController isKindOfClass:objc_getClass("GlowSettingsViewController")])) {
            return;
        }
        
        g_isSettingsPresenting = YES;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            g_isSettingsPresenting = NO;
        });

        @try {
            GlowSettingsViewController *vc = [[GlowSettingsViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            
            [top presentViewController:nav animated:YES completion:^{
                LOG("[ui] settings presented successfully\n");
            }];
        } @catch (NSException *e) {
            LOG("[ui] settings presentation exc: %s\n", e.reason.UTF8String);
        }
    });
}

@interface GlowSettingsLongPressHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation GlowSettingsLongPressHandler
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        LOG("[ui] tab bar item long press triggered on %s %p, opening settings\n",
            class_getName(object_getClass(gr.view)), gr.view);
        openGlowSettings();
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end

static GlowSettingsLongPressHandler *g_lpHandler = nil;
static NSMutableSet *g_viewsWithLongPress = nil;

static void addSettingsGestureToTabBarItem(UIView *item) {
    if (!item) return;
    @try {
        if (!g_viewsWithLongPress) {
            g_viewsWithLongPress = [[NSMutableSet alloc] init];
        }
        
        NSValue *val = [NSValue valueWithNonretainedObject:item];
        if ([g_viewsWithLongPress containsObject:val]) {
            return;
        }

        if (!g_lpHandler) {
            g_lpHandler = [[GlowSettingsLongPressHandler alloc] init];
        }

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:g_lpHandler
            action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.55;
        lp.cancelsTouchesInView = YES;
        lp.delegate = g_lpHandler;
        [item addGestureRecognizer:lp];
        
        [g_viewsWithLongPress addObject:val];
        g_tabBarGestureInstalled = YES;
        objc_setAssociatedObject(item, kGlowSettingsLPKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LOG("[ui] added settings long press gesture strictly to tab icon %s %p\n", 
            class_getName(object_getClass(item)), item);
    } @catch (NSException *e) {
        LOG("[ui] failed to add long press to TabBar item: %s\n", e.reason.UTF8String);
    }
}

static void tryAddLongPressToView(UIView *v) {
    if (!v) return;
    
    const char *className = class_getName(object_getClass(v));
    if (!className) return;

    // STRICT FILTER: ONLY match bottom tab bar icon buttons
    BOOL isTabBarIcon = (strcmp(className, "FBTabBarItemDefaultView") == 0) ||
                        (strcmp(className, "FBTabBarItemView") == 0) ||
                        (strcmp(className, "UITabBarButton") == 0);

    if (!isTabBarIcon) return;

    // Size check for icon buttons
    if (v.frame.size.width < 25 || v.frame.size.height < 20 || v.frame.size.height > 120) return;

    addSettingsGestureToTabBarItem(v);
}

static void walkViewsForLongPress(UIView *v, int depth) {
    if (!v || depth > 8) return;
    tryAddLongPressToView(v);
    for (UIView *sub in v.subviews) {
        walkViewsForLongPress(sub, depth + 1);
    }
}

void installLongPressOnCurrentUI(void) {
    if (!g_viewsWithLongPress) {
        g_viewsWithLongPress = [[NSMutableSet alloc] init];
    }
    if (!g_lpHandler) {
        g_lpHandler = [[GlowSettingsLongPressHandler alloc] init];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIApplication *app = [UIApplication sharedApplication];
            if (@available(iOS 13.0, *)) {
                for (id scene in [app connectedScenes]) {
                    if ([scene isKindOfClass:objc_getClass("UIWindowScene")]) {
                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *w in ws.windows) {
                            walkViewsForLongPress(w, 0);
                        }
                    }
                }
            } else {
                for (UIWindow *w in [app windows]) {
                    walkViewsForLongPress(w, 0);
                }
            }
        } @catch (NSException *e) {
            LOG("[ui] installLongPressOnCurrentUI exc: %s\n", e.reason.UTF8String);
        }
    });
}

// Hook FBTabBarItemDefaultView and UITabBar layoutSubviews to ensure icons receive the gesture
%hook FBTabBarItemDefaultView
- (void)layoutSubviews {
    %orig;
    addSettingsGestureToTabBarItem((UIView *)self);
}
%end

%hook UITabBar
- (void)layoutSubviews {
    %orig;
    for (UIView *sub in [self subviews]) {
        tryAddLongPressToView(sub);
    }
}
%end

void initLongPressHooks(void) {
    @try {
        %init;
        LOG("  hook: Strict TabBar icon long press hooks initialized\n");
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}

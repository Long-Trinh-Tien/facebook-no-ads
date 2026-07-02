// Core/LongPressHooks.xm
// Targeted proactive walk views approach, restricting settings gesture ONLY to the tab bar (FBTabBar) and tab bar items (FBTabBarItemDefaultView), excluding full-screen container views.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "UI/GlowSettingsViewController.h"
#import "Utils/GlowViewUtils.h"
#import "Utils/GlowCommon.h"

static IMP orig_tabbar_didMoveToWindow = NULL;
static IMP orig_tabbar_layoutSubviews = NULL;
static const void *kGlowSettingsLPKey = &kGlowSettingsLPKey;
static BOOL g_isSettingsPresenting = NO;

static void openGlowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_isSettingsPresenting) return;
        
        UIViewController *top = [GlowViewUtils topViewController];
        if (!top) {
            LOG("[ui] failed to find top view controller to present settings\n");
            return;
        }
        
        // Prevent presentation if the top VC is already the GlowSettingsViewController
        if ([top isKindOfClass:objc_getClass("GlowSettingsViewController")] ||
            ([top isKindOfClass:[UINavigationController class]] && 
             [((UINavigationController *)top).topViewController isKindOfClass:objc_getClass("GlowSettingsViewController")])) {
            return;
        }
        
        g_isSettingsPresenting = YES;
        
        // Debounce: reset the presenting flag after 1.0 second cooldown
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
        LOG("[ui] tab bar long press triggered on %s %p, opening settings\n",
            class_getName(object_getClass(gr.view)), gr.view);
        openGlowSettings();
    }
}

// Force simultaneous recognition so Facebook's native gesture recognizers do not block our settings gesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

// CRITICAL: Precedence override. Force Facebook's native gestures to wait for our long press to fail (meaning ours takes precedence and overrides them)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end

static GlowSettingsLongPressHandler *g_lpHandler = nil;
static NSMutableSet *g_viewsWithLongPress = nil;

static void addSettingsGestureToTabBar(UIView *tabBar) {
    if (!tabBar) return;
    @try {
        if (!g_viewsWithLongPress) {
            g_viewsWithLongPress = [[NSMutableSet alloc] init];
        }
        
        NSValue *val = [NSValue valueWithNonretainedObject:tabBar];
        if ([g_viewsWithLongPress containsObject:val]) {
            return;
        }

        if (!g_lpHandler) {
            g_lpHandler = [[GlowSettingsLongPressHandler alloc] init];
        }

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:g_lpHandler
            action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.8;
        lp.cancelsTouchesInView = YES; // Cancel other touches in view once our long press is recognized
        lp.delegate = g_lpHandler;     // Set delegate for precedence override
        [tabBar addGestureRecognizer:lp];
        
        [g_viewsWithLongPress addObject:val];
        objc_setAssociatedObject(tabBar, kGlowSettingsLPKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LOG("[ui] added settings long press gesture to %s %p\n", 
            class_getName(object_getClass(tabBar)), tabBar);
    } @catch (NSException *e) {
        LOG("[ui] failed to add long press to UITabBar: %s\n", e.reason.UTF8String);
    }
}

// UITabBar didMoveToWindow takes NO arguments. We must match the signature exactly.
static void hooked_tabbar_didMoveToWindow(id self, SEL _cmd) {
    if (orig_tabbar_didMoveToWindow) {
        typedef void (*Fn)(id, SEL);
        ((Fn)orig_tabbar_didMoveToWindow)(self, _cmd);
    }
    
    // CRITICAL: Only apply to UITabBar instances to prevent generic UIView hooking
    if (![self isKindOfClass:objc_getClass("UITabBar")]) return;
    
    addSettingsGestureToTabBar((UIView *)self);
}

// UITabBar layoutSubviews takes NO arguments. We must match the signature exactly.
static void hooked_tabbar_layoutSubviews(id self, SEL _cmd) {
    if (orig_tabbar_layoutSubviews) {
        typedef void (*Fn)(id, SEL);
        ((Fn)orig_tabbar_layoutSubviews)(self, _cmd);
    }
    
    // CRITICAL: Only apply to UITabBar instances to prevent generic UIView hooking
    if (![self isKindOfClass:objc_getClass("UITabBar")]) return;
    
    addSettingsGestureToTabBar((UIView *)self);
}

// Proactive view walking restricted strictly to exact Tab Bar (FBTabBar) and Tab Bar Items (FBTabBarItemDefaultView)
static void tryAddLongPressToView(UIView *v) {
    if (!v) return;
    
    const char *className = class_getName(object_getClass(v));
    
    // STRICT FILTER: Only allow standard UITabBar subclasses or exact Facebook tab bar class names.
    // This prevents matching full-screen container views like FBTabBarAndContentView or FBTabBarContainerView.
    BOOL isTabBar = [v isKindOfClass:[UITabBar class]] ||
                    [v isKindOfClass:objc_getClass("UITabBar")] ||
                    (className && (
                        strcmp(className, "FBTabBar") == 0 ||
                        strcmp(className, "FBTabBarItemDefaultView") == 0
                    ));

    if (!isTabBar) return;

    if (![v isUserInteractionEnabled]) return;
    
    // Width and height check (tab bar items are small but wide enough, usually 86x52)
    if (v.frame.size.width < 50 || v.frame.size.height < 25) return;

    addSettingsGestureToTabBar(v);
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

void initLongPressHooks(void) {
    @try {
        Class cls = objc_getClass("UITabBar");
        if (cls) {
            // Hook didMoveToWindow
            SEL sel = @selector(didMoveToWindow);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                orig_tabbar_didMoveToWindow = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_tabbar_didMoveToWindow);
                LOG("  hook: UITabBar.didMoveToWindow -> add settings long press\n");
            }
            
            // Hook layoutSubviews as fallback if didMoveToWindow fired before hooks installation
            SEL lsSel = @selector(layoutSubviews);
            Method lsM = class_getInstanceMethod(cls, lsSel);
            if (lsM) {
                orig_tabbar_layoutSubviews = method_getImplementation(lsM);
                method_setImplementation(lsM, (IMP)hooked_tabbar_layoutSubviews);
                LOG("  hook: UITabBar.layoutSubviews -> add settings long press (fallback)\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}

// LongPressHooks.xm
// Long press to open Glow settings UI
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCommon.h"

static IMP orig_sendAction = NULL;

static BOOL hooked_sendAction(id self, SEL _cmd, SEL action, id target, id sender, UIEvent *event) {
    // Always call original
    BOOL result = orig_sendAction ?
        ((BOOL(*)(id, SEL, SEL, id, id, id))orig_sendAction)(self, _cmd, action, target, sender, event) :
        YES;

    // Detect long press
    if (sender && [sender isKindOfClass:[UILongPressGestureRecognizer class]]) {
        UILongPressGestureRecognizer *lp = (UILongPressGestureRecognizer *)sender;
        if (lp.state == UIGestureRecognizerStateBegan) {
            LOG("[ui] long press detected, opening settings\n");
            dispatch_async(dispatch_get_main_queue(), ^{
                // Open settings - simple alert for now
                UIWindow *win = nil;
                if (@available(iOS 13.0, *)) {
                    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            for (UIWindow *w in scene.windows) {
                                if (w.isKeyWindow) { win = w; break; }
                            }
                        }
                        if (win) break;
                    }
                }
                if (!win) win = [UIApplication sharedApplication].keyWindow;
                if (!win) return;

                UIViewController *top = win.rootViewController;
                while (top.presentedViewController) top = top.presentedViewController;

                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"Glow Settings"
                    message:@"v8.3.0 - Modular Refactor"
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction
                    actionWithTitle:@"OK"
                    style:UIAlertActionStyleDefault
                    handler:nil]];
                [top presentViewController:alert animated:YES completion:nil];
            });
        }
    }
    return result;
}

void initLongPressHooks(void) {
    @try {
        Class appCls = objc_getClass("UIApplication");
        if (appCls) {
            SEL sel = sel_registerName("sendAction:to:from:forEvent:");
            Method m = class_getInstanceMethod(appCls, sel);
            if (m) {
                orig_sendAction = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_sendAction);
                LOG("  hook: UIApplication.sendAction:to:from:forEvent: -> long press detection\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}

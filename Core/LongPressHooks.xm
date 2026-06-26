// LongPressHooks.xm
// Long press to open Glow settings UI
// FIX v8.3.2: Make crash-safe - just log, no alert presentation
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCommon.h"

static IMP orig_sendAction = NULL;

// FIX v8.3.2: Removed alert presentation (was causing crash when rootViewController nil)
// Now just logs - settings are opened via StoryDownloadHooks self-add gesture
static BOOL hooked_sendAction(id self, SEL _cmd, SEL action, id target, id sender, UIEvent *event) {
    // Always call original first (critical for app functionality)
    BOOL result = orig_sendAction ?
        ((BOOL(*)(id, SEL, SEL, id, id, id))orig_sendAction)(self, _cmd, action, target, sender, event) :
        YES;

    // Detect long press safely
    @try {
        if (sender && [sender isKindOfClass:[UILongPressGestureRecognizer class]]) {
            UILongPressGestureRecognizer *lp = (UILongPressGestureRecognizer *)sender;
            if (lp.state == UIGestureRecognizerStateBegan) {
                // Just log - no alert (avoids crash on nil rootViewController)
                LOG("[ui] long press detected (gesture works, no alert)\n");
                // Settings are opened via StoryDownloadHooks self-add gesture
                // (GlowStoryHandler.onStoryLongPress:)
            }
        }
    } @catch (NSException *e) {
        // Silently catch any exception from long press detection
        LOG("[dl/longpress] sendAction exc: %s\n", e.reason.UTF8String);
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
                LOG("  hook: UIApplication.sendAction:to:from:forEvent: (safe log only)\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}

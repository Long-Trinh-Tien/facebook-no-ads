// Core/LikeConfirmHooks.xm
// Confirmation dialogs before Liking posts or Reels to prevent accidental taps
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"
#import "Utils/GlowViewUtils.h"

static IMP orig_app_sendAction = NULL;
static BOOL g_isConfirmingLike = NO;

// Helper to determine if a view or control is a Like / Reaction button
static BOOL isLikeButton(id sender) {
    if (!sender) return NO;
    @try {
        if ([sender respondsToSelector:@selector(accessibilityLabel)]) {
            NSString *label = [sender accessibilityLabel];
            if (label && [label isKindOfClass:[NSString class]]) {
                NSString *lower = [label lowercaseString];
                if ([lower containsString:@"thích"] || [lower containsString:@"like"]) {
                    // Make sure it is not "unlike" / "bỏ thích"
                    if (![lower containsString:@"bỏ thích"] && ![lower containsString:@"unlike"] && ![lower containsString:@"đã thích"]) {
                        return YES;
                    }
                }
            }
        }

        const char *className = class_getName(object_getClass(sender));
        if (className) {
            if (strstr(className, "LikeButton") != NULL ||
                strstr(className, "FeedbackReaction") != NULL ||
                strstr(className, "ReactionsUFIButton") != NULL) {
                return YES;
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

// Helper to check if button is in Reels context
static BOOL isInsideReels(UIView *view) {
    UIResponder *r = (UIResponder *)view;
    while (r) {
        const char *name = class_getName(object_getClass(r));
        if (name && (strstr(name, "Shorts") != NULL || strstr(name, "Reel") != NULL)) {
            return YES;
        }
        r = [r nextResponder];
    }
    return NO;
}

static BOOL hooked_app_sendAction(id self, SEL _cmd, SEL action, id target, id sender, UIEvent *event) {
    if (g_isConfirmingLike) {
        if (orig_app_sendAction) {
            typedef BOOL (*FnType)(id, SEL, SEL, id, id, id);
            return ((FnType)orig_app_sendAction)(self, _cmd, action, target, sender, event);
        }
        return YES;
    }

    GlowSettingsManager *sm = [GlowSettingsManager shared];

    if (isLikeButton(sender)) {
        BOOL inReels = [sender isKindOfClass:[UIView class]] && isInsideReels((UIView *)sender);
        BOOL shouldConfirm = (inReels && sm.confirmReelsLike) || (!inReels && sm.confirmLike);

        if (shouldConfirm) {
            UIViewController *top = [GlowViewUtils topViewController];
            if (top) {
                NSString *title = inReels ? @"Xác nhận thích Reels" : @"Xác nhận thích bài viết";
                NSString *msg = inReels ? @"Bạn có chắc chắn muốn thích video Reels này không?" : @"Bạn có chắc chắn muốn thích bài viết này không?";

                UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Thích" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
                    g_isConfirmingLike = YES;
                    if (orig_app_sendAction) {
                        typedef BOOL (*FnType)(id, SEL, SEL, id, id, id);
                        ((FnType)orig_app_sendAction)(self, _cmd, action, target, sender, event);
                    }
                    g_isConfirmingLike = NO;
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

                [top presentViewController:alert animated:YES completion:nil];
                return YES; // Intercept and wait for confirmation
            }
        }
    }

    if (orig_app_sendAction) {
        typedef BOOL (*FnType)(id, SEL, SEL, id, id, id);
        return ((FnType)orig_app_sendAction)(self, _cmd, action, target, sender, event);
    }
    return YES;
}

void initLikeConfirmHooks(void) {
    @try {
        Class appCls = objc_getClass("UIApplication");
        if (appCls) {
            SEL sel = @selector(sendAction:to:from:forEvent:);
            Method m = class_getInstanceMethod(appCls, sel);
            if (m && !orig_app_sendAction) {
                orig_app_sendAction = method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_app_sendAction);
                LOG("  hook: UIApplication.sendAction:to:from:forEvent: -> Like confirmation initialized\n");
            }
        }
    } @catch (NSException *e) {
        LOG("[like/confirm] init exc: %s\n", e.reason.UTF8String);
    }
}

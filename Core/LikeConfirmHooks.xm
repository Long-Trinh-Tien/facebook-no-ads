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
static BOOL g_isAlertCurrentlyPresented = NO;

// Helper to determine if a view or control is STRICTLY a Like / Reaction button
static BOOL isLikeButton(id sender, SEL action) {
    if (!sender) return NO;
    @try {
        // 1. Exclude text expansion / See More / Navigation / Truncation actions immediately
        if (action) {
            NSString *actionName = NSStringFromSelector(action);
            if ([actionName containsString:@"SeeMore"] ||
                [actionName containsString:@"seeMore"] ||
                [actionName containsString:@"truncate"] ||
                [actionName containsString:@"Truncat"] ||
                [actionName containsString:@"expand"] ||
                [actionName containsString:@"Expand"] ||
                [actionName containsString:@"text"] ||
                [actionName containsString:@"Text"] ||
                [actionName containsString:@"navigate"] ||
                [actionName containsString:@"didTapMedia"]) {
                return NO;
            }
        }

        // 2. Exclude text views, labels, scroll views, entire story containers
        const char *className = class_getName(object_getClass(sender));
        if (className) {
            if (strstr(className, "Text") != NULL ||
                strstr(className, "Label") != NULL ||
                strstr(className, "Scroll") != NULL ||
                strstr(className, "Cell") != NULL ||
                strstr(className, "FeedStory") != NULL) {
                return NO;
            }
        }

        // 3. Check view dimensions: A Like button is never full post size (height 20-60, width < 160)
        if ([sender isKindOfClass:[UIView class]]) {
            UIView *v = (UIView *)sender;
            CGSize sz = v.bounds.size;
            if (sz.height > 80 || sz.height < 15 || sz.width > 200 || sz.width < 20) {
                return NO;
            }
        }

        // 4. Strict Accessibility Label check
        if ([sender respondsToSelector:@selector(accessibilityLabel)]) {
            NSString *label = [sender accessibilityLabel];
            if (label && [label isKindOfClass:[NSString class]]) {
                NSString *lower = [[label lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                // Exclude aggregated labels containing counts or post content
                if ([lower containsString:@"lượt thích"] ||
                    [lower containsString:@"người thích"] ||
                    [lower containsString:@"bình luận"] ||
                    [lower containsString:@"chia sẻ"] ||
                    [lower containsString:@"xem thêm"] ||
                    [lower containsString:@"bỏ thích"] ||
                    [lower containsString:@"đã thích"] ||
                    [lower containsString:@"unlike"]) {
                    return NO;
                }

                // Strict matching for actual Like button
                if ([lower isEqualToString:@"thích"] ||
                    [lower isEqualToString:@"like"] ||
                    [lower hasPrefix:@"thích,"] ||
                    [lower hasPrefix:@"like,"] ||
                    [lower hasPrefix:@"nút thích"] ||
                    [lower hasPrefix:@"like button"]) {
                    return YES;
                }
            }
        }

        // 5. Specific class names for explicit Like / Reaction buttons
        if (className) {
            if (strcmp(className, "FBReelLikeButton") == 0 ||
                strcmp(className, "FBFeedFeedbackLikeButton") == 0 ||
                strcmp(className, "FDSCommentUFIButtonComponent") == 0) {
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

    if (isLikeButton(sender, action)) {
        BOOL inReels = [sender isKindOfClass:[UIView class]] && isInsideReels((UIView *)sender);
        BOOL shouldConfirm = (inReels && sm.confirmReelsLike) || (!inReels && sm.confirmLike);

        if (shouldConfirm) {
            if (g_isAlertCurrentlyPresented) {
                return YES; // Prevent duplicate popup when multiple touch events fire
            }
            g_isAlertCurrentlyPresented = YES;

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
                    g_isAlertCurrentlyPresented = NO;
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull a) {
                    g_isAlertCurrentlyPresented = NO;
                }]];

                [top presentViewController:alert animated:YES completion:nil];
                return YES; // Intercept and wait for confirmation
            } else {
                g_isAlertCurrentlyPresented = NO;
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

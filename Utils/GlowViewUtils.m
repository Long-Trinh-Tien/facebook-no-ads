// GlowViewUtils.m
#import "GlowViewUtils.h"
#import "GlowLogManager.h"
#import "GlowCommon.h"
#import <objc/runtime.h>

@implementation GlowViewUtils

+ (void)showSafeToast:(NSString *)message {
    if (!message) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *keyWindow = [self keyWindow];
            if (!keyWindow) return;

            UILabel *toastLabel = [[UILabel alloc] init];
            toastLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
            toastLabel.textColor = [UIColor whiteColor];
            toastLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
            toastLabel.textAlignment = NSTextAlignmentCenter;
            toastLabel.text = message;
            toastLabel.alpha = 1.0;
            toastLabel.layer.cornerRadius = 20;
            toastLabel.clipsToBounds = YES;
            toastLabel.numberOfLines = 0;
            [keyWindow addSubview:toastLabel];

            CGSize sz = [message boundingRectWithSize:CGSizeMake(keyWindow.frame.size.width - 80, 200)
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:@{NSFontAttributeName: toastLabel.font}
                                              context:nil].size;
            toastLabel.frame = CGRectMake((keyWindow.frame.size.width - sz.width - 30) / 2,
                                          keyWindow.frame.size.height - 200,
                                          sz.width + 30, sz.height + 18);

            [UIView animateWithDuration:0.4 delay:2.0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{ toastLabel.alpha = 0.0; }
                             completion:^(BOOL finished) { [toastLabel removeFromSuperview]; }];
        } @catch (NSException *e) {
            LOG("[dl/safe_toast] exc: %s\n", e.reason.UTF8String);
        }
    });
}

+ (void)showToast:(NSString *)message {
    [self showSafeToast:message];
}

+ (UIWindow *)keyWindow {
    if (@available(iOS 13.0, *)) {
        for (id scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *window in ws.windows) {
                        if (window.isKeyWindow) {
                            return window;
                        }
                    }
                }
            }
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

+ (UIViewController *)topViewController {
    UIWindow *win = [self keyWindow];
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

+ (UIView *)walkSuperviewFrom:(UIView *)view matchingClass:(Class)cls {
    while (view) {
        if ([view isKindOfClass:cls]) {
            return view;
        }
        view = view.superview;
    }
    return nil;
}

+ (UIView *)walkSuperviewFrom:(UIView *)view matchingClassName:(NSString *)name {
    while (view) {
        if (view.superview) {
            const char *clsName = class_getName(object_getClass(view.superview));
            if (clsName && strstr(clsName, [name UTF8String])) {
                return view.superview;
            }
        }
        view = view.superview;
    }
    return nil;
}

+ (UIResponder *)walkResponderChainFrom:(UIResponder *)responder
                                 matching:(BOOL(^)(UIResponder *))matcher {
    int depth = 0;
    while (responder && depth < 20) {
        if (matcher(responder)) {
            return responder;
        }
        responder = [responder nextResponder];
        depth++;
    }
    return nil;
}

@end

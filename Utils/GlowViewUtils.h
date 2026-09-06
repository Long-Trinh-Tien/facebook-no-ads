// GlowViewUtils.h
// UI utility functions (toast, bundle assets, view walking, etc.)
#import <UIKit/UIKit.h>

@interface GlowViewUtils : NSObject

+ (void)showToast:(NSString *)message;
+ (void)showSafeToast:(NSString *)message;

// Bundle & Asset Helpers
+ (NSBundle *)glowBundle;
+ (UIImage *)glowImageNamed:(NSString *)name;

// Find a UIWindow in the current scene
+ (UIWindow *)keyWindow;

// Find top view controller
+ (UIViewController *)topViewController;

// Walk view hierarchy
+ (UIView *)walkSuperviewFrom:(UIView *)view matchingClass:(Class)cls;
+ (UIView *)walkSuperviewFrom:(UIView *)view matchingClassName:(NSString *)name;

// Walk responder chain
+ (UIResponder *)walkResponderChainFrom:(UIResponder *)responder matching:(BOOL(^)(UIResponder *))matcher;

@end

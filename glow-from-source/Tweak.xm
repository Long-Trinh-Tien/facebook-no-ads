// STAGE 1 — Hook Engine Validation (v4)
// Use MSHookMessageEx via CydiaSubstrate (auto-injected by cyan)
// MSHookMessageEx handles subclass overrides correctly.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class _Class, SEL _cmd, IMP _replacement, IMP *_result);

__attribute__((constructor))
static void glow_init(void) {
  static IMP orig_viewWillAppear;
  MSHookMessageEx([UIViewController class], @selector(viewWillAppear:),
    imp_implementationWithBlock(^(id self, SEL _cmd, BOOL animated) {
      ((void(*)(id, SEL, BOOL))orig_viewWillAppear)(self, _cmd, animated);
      
      static dispatch_once_t once;
      dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
          NSString *vcName = NSStringFromClass([self class]);
          UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"STAGE 1 — MSHookMessageEx OK"
            message:[NSString stringWithFormat:@"First hooked VC: %@\n\nSubclass overrides handled correctly.", vcName]
            preferredStyle:UIAlertControllerStyleAlert];
          [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
          UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
          if (root) [root presentViewController:alert animated:YES completion:nil];
        });
      });
    }), &orig_viewWillAppear);
}

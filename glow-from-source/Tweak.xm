// STAGE 1 — Hook Engine Validation (v3)
// Simplest possible test: alert when viewWillAppear: fires.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

__attribute__((constructor))
static void glow_init(void) {
  Class cls = [UIViewController class];
  SEL sel = @selector(viewWillAppear:);
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) return;
  
  IMP new = imp_implementationWithBlock(^(id self, SEL _cmd, BOOL animated) {
    ((void(*)(id, SEL, BOOL))method_getImplementation(m))(self, _cmd, animated);
    
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      dispatch_async(dispatch_get_main_queue(), ^{
        NSString *vcName = NSStringFromClass([self class]);
        UIAlertController *alert = [UIAlertController
          alertControllerWithTitle:@"STAGE 1 — Swizzle OK"
          message:[NSString stringWithFormat:@"First VC: %@\nmethod_setImplementation works!", vcName]
          preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
          style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (root) [root presentViewController:alert animated:YES completion:nil];
      });
    });
  });
  
  // Try class_replaceMethod instead (more compatible)
  class_replaceMethod(cls, sel, new, method_getTypeEncoding(m));
}

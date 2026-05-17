// STAGE 1 — Hook Engine Validation
// Question: Does raw ObjC runtime swizzling work?
// Visual proof: UIAlert shows first 10 VC class names caught by swizzle.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSMutableArray *caughtVCs = nil;
static dispatch_once_t showOnce;

__attribute__((constructor))
static void glow_init(void) {
  caughtVCs = [NSMutableArray new];
  
  // Raw swizzle: replace UIViewController.viewWillAppear:
  Class cls = [UIViewController class];
  SEL sel = @selector(viewWillAppear:);
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) return;
  
  IMP orig = method_getImplementation(m);
  IMP new = imp_implementationWithBlock(^(id self, SEL _cmd, BOOL animated) {
    ((void(*)(id, SEL, BOOL))orig)(self, _cmd, animated);
    
    // Collect first 10 VC class names
    if (caughtVCs.count < 10) {
      NSString *name = NSStringFromClass([self class]);
      if (name) [caughtVCs addObject:name];
    }
    
    // Show alert after 10 VCs or 3s
    dispatch_once(&showOnce, ^{
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          if (caughtVCs.count == 0) return;
          NSString *msg = [NSString stringWithFormat:@"Swizzle works!\n\nCaught %lu VCs:\n%@",
            (unsigned long)caughtVCs.count,
            [caughtVCs componentsJoinedByString:@"\n"]];
          UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Glow STAGE 1"
            message:msg preferredStyle:UIAlertControllerStyleAlert];
          [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
          UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
          if (root) [root presentViewController:alert animated:YES completion:nil];
        });
    });
  });
  
  method_setImplementation(m, new);
}

// STAGE 1 — Hook Engine Validation
// Question: Does raw ObjC runtime swizzling work?
// 
// Test: method_setImplementation on UIViewController.viewWillAppear:
// No Logos, no Facebook classes. Pure runtime API.
// If os_log appears → hook engine works.
//
// Build này chỉ trả lời: "Swizzle có hoạt động không?"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>

static os_log_t glowLog(void) {
  static os_log_t l;
  static dispatch_once_t t;
  dispatch_once(&t, ^{ l = os_log_create("com.glow.stage1", "HookTest"); });
  return l;
}

__attribute__((constructor))
static void glow_init(void) {
  // Raw swizzle: replace UIViewController.viewWillAppear:
  Class cls = [UIViewController class];
  SEL sel = @selector(viewWillAppear:);
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) return;
  
  IMP orig = method_getImplementation(m);
  IMP new = imp_implementationWithBlock(^(id self, SEL _cmd, BOOL animated) {
    os_log_info(glowLog(), "[stage1] viewWillAppear: %{public}@", NSStringFromClass([self class]));
    ((void(*)(id, SEL, BOOL))orig)(self, _cmd, animated);
  });
  
  method_setImplementation(m, new);
}

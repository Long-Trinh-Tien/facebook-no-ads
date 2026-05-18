// Phase 2C — Floating debug button
// UIAction-based (iOS 14+), no class_addMethod complexity

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <objc/runtime.h>

static IMP (*orig_dtm)(id, SEL) = NULL;

static void mark(UIView *v, int d) {
  if (!v || d > 15 || v.hidden) return;
  CGRect f = v.frame;
  CGFloat sw = UIScreen.mainScreen.bounds.size.width;
  
  BOOL hc = NO, hs = NO;
  for (UIView *s in v.subviews) {
    if ([s isKindOfClass:UICollectionView.class]) hc = YES;
    if ([s isKindOfClass:UIScrollView.class]) hs = YES;
  }
  
  UIColor *c = nil;
  CGFloat bw = 0;
  if (f.size.width >= sw - 10 && d <= 3) { c = UIColor.redColor; bw = 3; }
  else if (hc && f.size.width > 150) { c = UIColor.blueColor; bw = 2; }
  else if (hs && f.size.width > 100) { c = UIColor.greenColor; bw = 2; }
  
  if (c) {
    v.layer.borderWidth = bw;
    v.layer.borderColor = c.CGColor;
  }
  for (UIView *s in v.subviews) mark(s, d + 1);
}

static void clear(UIView *v) {
  if (!v) return;
  v.layer.borderWidth = 0;
  v.layer.borderColor = nil;
  for (UIView *s in v.subviews) clear(s);
}

static void inspect(void) {
  UIWindow *w = UIApplication.sharedApplication.keyWindow;
  if (!w) w = UIApplication.sharedApplication.delegate.window;
  if (!w) return;
  clear(w);
  mark(w, 0);
}

static void setupButton(void) {
  UIWindow *dw = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
  dw.windowLevel = UIWindowLevelAlert + 1000;
  dw.backgroundColor = UIColor.clearColor;
  
  UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
  b.frame = CGRectMake(0, 0, 44, 44);
  b.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:1 alpha:0.35];
  b.layer.cornerRadius = 22;
  b.clipsToBounds = YES;
  [b setTitle:@"☰" forState:UIControlStateNormal];
  b.titleLabel.font = [UIFont boldSystemFontOfSize:18];
  
  if (@available(iOS 14.0, *)) {
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { inspect(); }]
         forControlEvents:UIControlEventTouchUpInside];
  }
  
  dw.rootViewController = [[UIViewController alloc] init];
  [dw.rootViewController.view addSubview:b];
  dw.frame = CGRectMake(16, 200, 44, 44);
  dw.hidden = NO;
}

static void hooked_dtm(id self, SEL _cmd) {
  if (orig_dtm) orig_dtm(self, _cmd);
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    dispatch_async(dispatch_get_main_queue(), ^{ setupButton(); });
  });
}

__attribute__((constructor))
static void glow_init(void) {
  Class c = objc_getClass("UIView");
  SEL s = sel_registerName("didMoveToWindow");
  Method m = class_getInstanceMethod(c, s);
  orig_dtm = (IMP(*)(id,SEL))method_getImplementation(m);
  method_setImplementation(m, (IMP)hooked_dtm);
}

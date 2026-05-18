// KNOWN_GOOD_BASELINE + STEP E: attach tiny red UIView to view.window
// Based on commit 980d557 (KNOWN_GOOD_HOOK_BASELINE)
// ONLY change: dispatch_async + addSubview to view.window

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <objc/runtime.h>

static IMP (*orig_dtm)(id, SEL) = NULL;

static void hooked_dtm(id self, SEL _cmd) {
  if (orig_dtm) orig_dtm(self, _cmd);
  
  const char *home = getenv("HOME");
  if (home) {
    char path[512];
    snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
    FILE *f = fopen(path, "a");
    if (f) {
      fprintf(f, "HOOK_FIRED: UIView %p didMoveToWindow\n", (void*)self);
      fclose(f);
    }
  }
  
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      UIView *view = (UIView *)self;
      UIWindow *win = view.window;
      if (win) {
        UIView *sq = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
        sq.backgroundColor = UIColor.redColor;
        [win addSubview:sq];
        
        if (home) {
          char path[512];
          snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
          FILE *f = fopen(path, "a");
          if (f) {
            fprintf(f, "RED_SQUARE_ADDED to window %p\n", (void*)win);
            fclose(f);
          }
        }
      }
    });
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

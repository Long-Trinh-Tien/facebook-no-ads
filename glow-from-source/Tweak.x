// STEP E debug: log inside async block to find exact failure point

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
      fprintf(f, "HOOK: UIView %p window=%p\n", (void*)self, (void*)((UIView*)self).window);
      fclose(f);
    }
  }
  
  // Only try when view has window
  UIView *view = (UIView *)self;
  if (!view.window) return;
  
  static BOOL done = NO;
  if (done) return;
  
  UIWindow *win = view.window;
  dispatch_async(dispatch_get_main_queue(), ^{
    // Log: did we enter the block?
    if (home) {
      char path[512];
      snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
      FILE *f = fopen(path, "a");
      if (f) {
        fprintf(f, "ASYNC_ENTER win=%p keyWin=%p\n",
                (void*)win, (void*)[UIApplication sharedApplication].keyWindow);
        fclose(f);
      }
    }
    
    // Use keyWindow as fallback
    UIWindow *target = win;
    if (!target) target = [UIApplication sharedApplication].keyWindow;
    if (!target) {
      if (home) {
        char path[512];
        snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
        FILE *f = fopen(path, "a");
        if (f) { fprintf(f, "NO_WINDOW\n"); fclose(f); }
      }
      return;
    }
    
    UIView *sq = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    sq.backgroundColor = UIColor.redColor;
    [target addSubview:sq];
    done = YES;
    
    if (home) {
      char path[512];
      snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
      FILE *f = fopen(path, "a");
      if (f) {
        fprintf(f, "RED_SQUARE_ADDED to %p\n", (void*)target);
        fclose(f);
      }
    }
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

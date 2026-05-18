// Minimal proof: UIWindowScene from live view, not from connectedScenes

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <objc/runtime.h>

static IMP (*orig_dtm)(id, SEL) = NULL;
static UIWindow *overlayWin = nil;

static void hooked_dtm(id self, SEL _cmd) {
  if (orig_dtm) orig_dtm(self, _cmd);
  
  if (overlayWin) return;  // already created
  
  // Get scene from the live view
  UIView *view = (UIView *)self;
  if (!view.window) return;
  UIWindowScene *scene = view.window.windowScene;
  if (!scene) return;
  
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      overlayWin = [[UIWindow alloc] initWithWindowScene:scene];
      overlayWin.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.2];
      overlayWin.windowLevel = 2100;
      overlayWin.hidden = NO;
      
      const char *home = getenv("HOME");
      if (!home) return;
      char path[512];
      snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
      FILE *f = fopen(path, "w");
      if (f) {
        fprintf(f, "OVERLAY CREATED\n");
        fprintf(f, "scene=%p overlayWin=%p hidden=%d\n",
                (void*)scene, (void*)overlayWin, overlayWin.hidden);
        fclose(f);
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

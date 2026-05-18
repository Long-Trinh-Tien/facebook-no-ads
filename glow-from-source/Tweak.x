// Minimal proof: UIWindowScene attachment test
// Fullscreen 20% red overlay — nothing else

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <objc/runtime.h>

static IMP (*orig_dtm)(id, SEL) = NULL;
static UIWindow *overlayWin = nil;

static void showOverlay(void) {
  UIWindowScene *activeScene = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:UIWindowScene.class] &&
        scene.activationState == UISceneActivationStateForegroundActive) {
      activeScene = (UIWindowScene *)scene;
      break;
    }
  }
  
  if (!activeScene) return;
  
  overlayWin = [[UIWindow alloc] initWithWindowScene:activeScene];
  overlayWin.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.2];
  overlayWin.windowLevel = 2100;
  overlayWin.hidden = NO;
  
  const char *home = getenv("HOME");
  if (!home) return;
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  FILE *f = fopen(path, "w");
  if (f) {
    fprintf(f, "OVERLAY ATTEMPTED\n");
    fprintf(f, "scenes=%lu\n", (unsigned long)UIApplication.sharedApplication.connectedScenes.count);
    fprintf(f, "activeScene=%p\n", (void*)activeScene);
    fprintf(f, "overlayWin=%p hidden=%d\n", (void*)overlayWin, overlayWin.hidden);
    fclose(f);
  }
}

static void hooked_dtm(id self, SEL _cmd) {
  if (orig_dtm) orig_dtm(self, _cmd);
  
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      showOverlay();
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

// Test: ObjC messaging inside hook IMP (runtime context — should work)
// Constructor: C runtime funcs only (confirmed working)

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

static IMP (*orig_dtm)(id, SEL) = NULL;

static void hooked_dtm(id self, SEL _cmd) {
  if (orig_dtm) orig_dtm(self, _cmd);
  
  if ([self isHidden]) return;
  CGRect f = [self frame];
  if (f.size.width < 200) return;
  
  [self setBackgroundColor:[UIColor redColor]];
}

__attribute__((constructor))
static void glow_init(void) {
  Class uiView = objc_getClass("UIView");
  SEL dtm = sel_registerName("didMoveToWindow");
  Method dtmM = class_getInstanceMethod(uiView, dtm);
  orig_dtm = (IMP(*)(id,SEL))method_getImplementation(dtmM);
  method_setImplementation(dtmM, (IMP)hooked_dtm);
  
  const char *home = getenv("HOME");
  if (!home) return;
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  FILE *f = fopen(path, "w");
  if (f) {
    fprintf(f, "VISUAL TEST: ObjC msg in hook context\n");
    fclose(f);
  }
}

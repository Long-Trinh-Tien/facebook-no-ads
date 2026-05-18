// Execution trace only — NO overlay, NO UI, NO visual effects
// Append-only markers to determine EXACTLY where flow stops

#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

#define MARK(s) do { \
  const char *home = getenv("HOME"); \
  if (!home) return; \
  char path[512]; \
  snprintf(path, sizeof(path), "%s/Documents/glow_trace.txt", home); \
  FILE *f = fopen(path, "a"); \
  if (f) { fprintf(f, "%s\n", s); fflush(f); fclose(f); } \
} while(0)

static IMP (*orig_dtm)(id, SEL) = NULL;

static void hooked_dtm(id self, SEL _cmd) {
  MARK("D_hook_callback_fire");
  
  if (orig_dtm) orig_dtm(self, _cmd);
  
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    MARK("E_main_queue_enter");
    
    dispatch_async(dispatch_get_main_queue(), ^{
      MARK("F_main_queue_callback");
      
      UIView *view = (UIView *)self;
      if (view.window) {
        MARK("G_view_window_not_nil");
        if (view.window.windowScene) {
          MARK("H_windowScene_not_nil");
        }
      }
    });
  });
}

__attribute__((constructor))
static void glow_init(void) {
  MARK("A_ctor_enter");
  
  Class c = objc_getClass("UIView");
  if (c) {
    MARK("B_UIView_class_found");
    SEL s = sel_registerName("didMoveToWindow");
    Method m = class_getInstanceMethod(c, s);
    if (m) {
      MARK("C_method_found");
      orig_dtm = (IMP(*)(id,SEL))method_getImplementation(m);
      method_setImplementation(m, (IMP)hooked_dtm);
      MARK("C_hook_installed");
    }
  }
}

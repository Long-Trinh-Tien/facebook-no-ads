#import <objc/runtime.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;
static IMP orig_setSeenState = NULL;

static void hook_setSeenState(id self, SEL _cmd, id state) {
  if (disableStorySeen) return;
  ((void(*)(id, SEL, id))orig_setSeenState)(self, _cmd, state);
}

// Attempt to hook class+method. Returns YES if hooked.
static BOOL tryHookClass(const char *className) {
  Class cls = objc_getClass(className);
  if (!cls) { NSLog(@"[noseen] class not found: %s", className); return NO; }

  SEL sel = @selector(setSeenState:);
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) { NSLog(@"[noseen] no setSeenState: on %s", className); return NO; }

  orig_setSeenState = method_getImplementation(m);
  method_setImplementation(m, (IMP)hook_setSeenState);
  NSLog(@"[noseen] HOOKED %s", className);
  return YES;
}

%ctor {
  @autoreleasepool {
    // Chỉ dlopen FBSharedFramework (cần cho class lookup), skip FBSharedDynamicFramework
    NSString *fwPath = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fwPath UTF8String], RTLD_NOW | RTLD_GLOBAL);

    // Thử từng class có setSeenState: tiềm năng
    const char *candidates[] = {
      "FBSnacksSurfaceAwareSeenStateWriter",
      "FBSnacksCardSeenStateInfo",
      "FBSnacksUnifiedSeenStateMutator",
      "FBShortsSeenStateMutator",
      "FBSnacksViewReceiptsSeenStateInfoDataSource",
      "FBSnacksSeenStateInfoDataSource",
    };

    int hooked = 0;
    for (int i = 0; i < sizeof(candidates)/sizeof(candidates[0]); i++) {
      if (tryHookClass(candidates[i])) hooked++;
    }
    NSLog(@"[noseen] hooked %d classes", hooked);
  }
}

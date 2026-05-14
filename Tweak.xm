#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

%ctor {
  @autoreleasepool {
    // Preload frameworks
    NSString *fwPaths[] = {
      @"Frameworks/FBSharedFramework.framework/FBSharedFramework",
      @"Frameworks/FBSharedDynamicFramework.framework/FBSharedDynamicFramework",
    };
    for (int i = 0; i < 2; i++) {
      NSString *path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:fwPaths[i]];
      dlopen([path UTF8String], RTLD_NOW | RTLD_GLOBAL);
    }

    SEL targetSel = @selector(setSeenState:);
    SEL seenStateSel = NSSelectorFromString(@"setSeenState:");

    // Scan tất cả class FB prefix
    int classCount = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    classCount = objc_getClassList(classes, classCount);

    NSLog(@"[noseen] scanning %d classes...", classCount);

    for (int i = 0; i < classCount; i++) {
      Class cls = classes[i];
      const char *name = class_getName(cls);
      if (strncmp(name, "FB", 2) != 0 && strncmp(name, "FBSnacks", 8) != 0) continue;

      // Tìm method setSeenState:
      Method m = class_getInstanceMethod(cls, targetSel);
      if (!m && seenStateSel) m = class_getInstanceMethod(cls, seenStateSel);
      if (!m) continue;

      // Lấy method signature để xác nhận
      const char *types = method_getTypeEncoding(m);
      NSLog(@"[noseen] FOUND: %s setSeenState: types=%s", name, types ? types : "?");
    }

    free(classes);
    NSLog(@"[noseen] scan done");
  }
}

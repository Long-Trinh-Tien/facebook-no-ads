#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

%ctor {
  @autoreleasepool {
    // Chỉ load FBSharedFramework, KHÔNG load FBSharedDynamicFramework
    NSString *path = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([path UTF8String], RTLD_NOW | RTLD_GLOBAL);

    // Scan tất cả class tìm setSeenState:
    SEL targetSel = @selector(setSeenState:);
    int classCount = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    classCount = objc_getClassList(classes, classCount);

    // Mảng lưu kết quả
    #define MAX_FOUND 50
    const char *found[MAX_FOUND];
    int foundCount = 0;

    for (int i = 0; i < classCount && foundCount < MAX_FOUND; i++) {
      Class cls = classes[i];
      const char *name = class_getName(cls);
      if (strncmp(name, "FB", 2) != 0 && strncmp(name, "FBSnacks", 8) != 0) continue;
      if (class_getInstanceMethod(cls, targetSel)) {
        found[foundCount++] = name;
      }
    }
    free(classes);

    // Log sau khi loop để tránh crash trong loop
    NSLog(@"[noseen] scanned %d classes, found %d:", classCount, foundCount);
    for (int i = 0; i < foundCount; i++) {
      NSLog(@"[noseen]   %s", found[i]);
    }
  }
}

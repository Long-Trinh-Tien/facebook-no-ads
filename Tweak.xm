#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;

// ─── Globals for per-class IMP storage ─────
static IMP orig_removeDataSource = NULL;
static IMP orig_invalidateCache = NULL;
static IMP orig_didUpdateSeen = NULL;

// ─── Hook: FBSnacksSurfaceAwareSeenStateWriter.removeSeenStateInfoDataSource ───
static void hook_removeDataSource(id self, SEL _cmd) {
  if (disableStorySeen) return;
  if (orig_removeDataSource) ((void(*)(id, SEL))orig_removeDataSource)(self, _cmd);
}

// ─── Hook: FBSnacksSurfaceAwareSeenStateWriter.invalidateSeenStateInfoCache ───
static void hook_invalidateCache(id self, SEL _cmd) {
  if (disableStorySeen) return;
  if (orig_invalidateCache) ((void(*)(id, SEL))orig_invalidateCache)(self, _cmd);
}

// ─── Hook: FBSnacksViewReceiptsSeenStateInfoDataSource.didUpdateSeenStateInfo:threadID: ───
static void hook_didUpdateSeen(id self, SEL _cmd, id info, id threadID) {
  if (disableStorySeen) return;
  if (orig_didUpdateSeen) ((void(*)(id, SEL, id, id))orig_didUpdateSeen)(self, _cmd, info, threadID);
}

// ─── Utility: try hook a void: method ───
static BOOL tryHookVoid(Class cls, const char *selName, IMP *origPtr, IMP hook) {
  SEL sel = sel_registerName(selName);
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) {
    NSLog(@"[noseen] no [%s %s]", class_getName(cls), selName);
    return NO;
  }
  *origPtr = method_getImplementation(m);
  method_setImplementation(m, hook);
  NSLog(@"[noseen] HOOKED [%s %s]", class_getName(cls), selName);
  return YES;
}

%ctor {
  @autoreleasepool {
    // Load framework để class available
    NSString *fw = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);

    int hooked = 0;

    // 1. FBSnacksSurfaceAwareSeenStateWriter.removeSeenStateInfoDataSource
    Class writer = objc_getClass("FBSnacksSurfaceAwareSeenStateWriter");
    if (writer) {
      if (tryHookVoid(writer, "removeSeenStateInfoDataSource", &orig_removeDataSource, (IMP)hook_removeDataSource))
        hooked++;
      if (tryHookVoid(writer, "invalidateSeenStateInfoCache", &orig_invalidateCache, (IMP)hook_invalidateCache))
        hooked++;
    }

    // 2. FBSnacksViewReceiptsSeenStateInfoDataSource.didUpdateSeenStateInfo:threadID:
    Class dataSrc = objc_getClass("FBSnacksViewReceiptsSeenStateInfoDataSource");
    if (dataSrc) {
      SEL sel = sel_registerName("didUpdateSeenStateInfo:threadID:");
      Method m = class_getInstanceMethod(dataSrc, sel);
      if (m) {
        orig_didUpdateSeen = method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_didUpdateSeen);
        hooked++;
        NSLog(@"[noseen] HOOKED [FBSnacksViewReceiptsSeenStateInfoDataSource didUpdateSeenStateInfo:threadID:]");
      }
    }

    NSLog(@"[noseen] hooked %d methods", hooked);
  }
}

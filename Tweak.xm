#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;

static IMP orig_attemptSend = NULL;
static void hook_attemptSend(id self, SEL _cmd, id response, id bucket) {
  if (disableStorySeen) { return; }
  if (orig_attemptSend) ((void(*)(id, SEL, id, id))orig_attemptSend)(self, _cmd, response, bucket);
}

static IMP orig_markSeen = NULL;
static void hook_markSeen(id self, SEL _cmd, id threads, id bucket, id tracking, BOOL isAnonymous, id completion) {
  if (disableStorySeen) { return; }
  if (orig_markSeen) ((void(*)(id, SEL, id, id, id, BOOL, id))orig_markSeen)(self, _cmd, threads, bucket, tracking, isAnonymous, completion);
}

// Directly call init functions from a loaded dylib's __init_offsets
static void callInitFunctions(void *handle) {
  if (!handle) return;
  
  // Get the mach header from dlopen
  struct mach_header_64 *header = NULL;
  Dl_info info;
  // Try to find the header from a known symbol in Glow.dylib
  // Since we can't use dlsym on constructors, we need a different approach
  
  // Alternative: find the image by iterating all loaded images
  uint32_t count = _dyld_image_count();
  for (uint32_t i = 0; i < count; i++) {
    const char *name = _dyld_get_image_name(i);
    if (name && strstr(name, "Glow.dylib")) {
      header = (struct mach_header_64 *)_dyld_get_image_header(i);
      break;
    }
  }
  
  if (!header) {
    NSLog(@"[noseen] Glow dylib header not found in loaded images");
    return;
  }
  
  // Find __init_offsets in the dylib
  unsigned long offsetSize = 0;
  uint32_t *offsets = (uint32_t *)getsectdatafromheader_64(
    header, "__DATA", "__init_offsets", &offsetSize);
    
  if (!offsets || offsetSize == 0) {
    // Try __mod_init_func
    void **modInit = (void **)getsectdatafromheader_64(
      header, "__DATA", "__mod_init_func", &offsetSize);
    if (modInit && offsetSize > 0) {
      int count = offsetSize / sizeof(void *);
      for (int j = 0; j < count; j++) {
        void (*initFunc)() = (void (*)())modInit[j];
        if (initFunc) {
          initFunc();
        }
      }
      NSLog(@"[noseen] called %d __mod_init_func for Glow", count);
    } else {
      NSLog(@"[noseen] no init sections found");
    }
    return;
  }
  
  // Process __init_offsets (relative offsets from the section itself)
  int count = offsetSize / sizeof(uint32_t);
  uintptr_t base = (uintptr_t)offsets;
  for (int j = 0; j < count; j++) {
    if (offsets[j] != 0) {
      void (*initFunc)() = (void (*)())(base - offsets[j]);
      initFunc();
    }
  }
  NSLog(@"[noseen] called %d __init_offsets for Glow", count);
}

%ctor {
  @autoreleasepool {
    NSString *glowPath = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/Glow.dylib"];
    
    void *handle = dlopen([glowPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
    NSLog(@"[noseen] Glow dlopen: %s", handle ? "OK" : dlerror());
    
    // Manually call Glow's constructors (Substrate có thể suppress chúng)
    callInitFunctions(handle);
    NSLog(@"[noseen] Glow constructors called manually");

    // Hook seen state
    Class cls = objc_getClass("FBSnacksUnifiedSeenStateMutator");
    if (!cls) {
      NSLog(@"[noseen] class not found");
      return;
    }
    
    SEL sel1 = sel_registerName("_attemptSendSeenStateAndHandleResponse:bucket:");
    Method m1 = class_getInstanceMethod(cls, sel1);
    if (m1) {
      orig_attemptSend = method_getImplementation(m1);
      method_setImplementation(m1, (IMP)hook_attemptSend);
      NSLog(@"[noseen] HOOKED _attemptSendSeenStateAndHandleResponse:bucket:");
    }
    
    SEL sel2 = sel_registerName("_markThreadsAsSeen:fromBucket:withTrackingString:isAnonymousView:completion:");
    Method m2 = class_getInstanceMethod(cls, sel2);
    if (m2) {
      orig_markSeen = method_getImplementation(m2);
      method_setImplementation(m2, (IMP)hook_markSeen);
      NSLog(@"[noseen] HOOKED _markThreadsAsSeen:");
    }
    
    NSLog(@"[noseen] init done");
  }
}

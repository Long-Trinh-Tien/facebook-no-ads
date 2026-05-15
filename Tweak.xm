#import <objc/runtime.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;

// ─── Hook: _attemptSendSeenStateAndHandleResponse:bucket: ───
// Method này gửi seen state mutation lên server. No-op = ko gửi.
static IMP orig_attemptSend = NULL;
static void hook_attemptSend(id self, SEL _cmd, id response, id bucket) {
  if (disableStorySeen) return;
  if (orig_attemptSend) ((void(*)(id, SEL, id, id))orig_attemptSend)(self, _cmd, response, bucket);
}

// ─── Hook: _markThreadsAsSeen:fromBucket:...:isAnonymousView:completion: ───
// Method này đánh dấu thread đã seen. No-op = ko đánh dấu.
static IMP orig_markSeen = NULL;
static void hook_markSeen(id self, SEL _cmd, id threads, id bucket, id tracking, BOOL isAnonymous, id completion) {
  if (disableStorySeen) return;
  if (orig_markSeen) ((void(*)(id, SEL, id, id, id, BOOL, id))orig_markSeen)(self, _cmd, threads, bucket, tracking, isAnonymous, completion);
}

%ctor {
  @autoreleasepool {
    Class cls = objc_getClass("FBSnacksUnifiedSeenStateMutator");
    if (!cls) { NSLog(@"[noseen] class not found"); return; }

    SEL sel1 = sel_registerName("_attemptSendSeenStateAndHandleResponse:bucket:");
    Method m1 = class_getInstanceMethod(cls, sel1);
    if (m1) {
      orig_attemptSend = method_getImplementation(m1);
      method_setImplementation(m1, (IMP)hook_attemptSend);
      NSLog(@"[noseen] HOOKED _attemptSendSeenStateAndHandleResponse:bucket:");
    } else {
      NSLog(@"[noseen] method1 not found");
    }

    SEL sel2 = sel_registerName("_markThreadsAsSeen:fromBucket:withTrackingString:isAnonymousView:completion:");
    Method m2 = class_getInstanceMethod(cls, sel2);
    if (m2) {
      orig_markSeen = method_getImplementation(m2);
      method_setImplementation(m2, (IMP)hook_markSeen);
      NSLog(@"[noseen] HOOKED _markThreadsAsSeen:fromBucket:withTrackingString:isAnonymousView:completion:");
    } else {
      NSLog(@"[noseen] method2 not found");
    }

    NSLog(@"[noseen] done");
  }
}

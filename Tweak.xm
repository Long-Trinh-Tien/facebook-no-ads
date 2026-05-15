#import <objc/runtime.h>
#import <Foundation/Foundation.h>

%ctor {
  @autoreleasepool {
    // Danh sách selectors tiềm năng cần kiểm tra
    const char *selectors[] = {
      "_sendSeenThreadIDsWithBucket:session:",
      "_attemptSendSeenStateAndHandleResponse:bucket:",
      "_markThreadAsSeen:bucket:session:shouldMarkThreadSeenStateUpdates:skipSeenMutationForLastUnseenThread:",
      "_markThreadsAsSeen:fromBucket:withTrackingString:isAnonymousView:completion:",
      "markThreadIDsAsSeen",
      "markThreadsViewReceiptsAndLightweightReactionsAsSeen:bucket:session:isHighlight:successBlock:noThreadsToMarkAsSeenBlock:",
      "markThreadStartWithIndex:",
      "setSeenState:",
      "setVideoCardSeenForPrimaryKey:",
    };

    // Danh sách class tiềm năng
    const char *classes[] = {
      "FBSnacksSurfaceAwareSeenStateWriter",
      "FBSnacksViewReceiptsSeenStateInfoDataSource",
      "FBSnacksUnifiedSeenStateMutator",
      "FBShortsSeenStateMutator",
    };
    int numClasses = sizeof(classes)/sizeof(classes[0]);
    int numSelectors = sizeof(selectors)/sizeof(selectors[0]);

    NSLog(@"[noseen] checking %d classes x %d selectors", numClasses, numSelectors);

    for (int c = 0; c < numClasses; c++) {
      Class cls = objc_getClass(classes[c]);
      if (!cls) { NSLog(@"[noseen] class not found: %s", classes[c]); continue; }

      for (int s = 0; s < numSelectors; s++) {
        SEL sel = sel_registerName(selectors[s]);
        if (class_getInstanceMethod(cls, sel)) {
          NSLog(@"[noseen] ✅ %s has %s", classes[c], selectors[s]);
        }
      }
    }
    NSLog(@"[noseen] check done");
  }
}

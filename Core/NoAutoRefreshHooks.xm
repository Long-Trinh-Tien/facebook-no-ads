// Core/NoAutoRefreshHooks.xm
// Prevents Facebook from auto-reloading feed and scrolling to top when returning from background
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

// 1. Freeze background time duration so Facebook's timeout threshold (30s-60s) never triggers
%hook FBBackgroundTimeState
- (NSTimeInterval)timeSinceLastBackgrounding {
    if ([GlowSettingsManager shared].disableAutoRefresh) {
        return 0.1; // Pretend app was only in background for 0.1s
    }
    return %orig;
}

- (double)backgroundTimeSpent {
    if ([GlowSettingsManager shared].disableAutoRefresh) {
        return 0.1;
    }
    return %orig;
}
%end

// 2. Block Warm Start handler from initiating automatic feed refresh
%hook FBNewsFeedWarmStartHandler
- (void)topOfFeedWarmStartRefreshData:(id)data isNewsFeedPresented:(BOOL)feedPres isTopOfNewsFeedPresented:(BOOL)topPres isInitiatedInBackground:(BOOL)inBg {
    if ([GlowSettingsManager shared].disableAutoRefresh) {
        LOG("[refresh] Blocked FBNewsFeedWarmStartHandler topOfFeedWarmStartRefreshData\n");
        return;
    }
    %orig;
}
%end

void initNoAutoRefreshHooks(void) {
    @try {
        %init;
        LOG("  hook: NoAutoRefreshHooks initialized (Background timer frozen at 0.1s)\n");
    } @catch (NSException *e) {
        LOG("[refresh] init exc: %s\n", e.reason.UTF8String);
    }
}

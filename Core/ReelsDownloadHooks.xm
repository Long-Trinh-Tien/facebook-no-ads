// ReelsDownloadHooks.xm - STUB
// Hooks for Reels download (FBShortsSideBarView)
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowLogManager.h"

void initReelsDownloadHooks(void) {
    if (![GlowSettingsManager shared].downloadReels) return;
    @try {
        // Full implementation will be in Phase 1.5
        LOG("  hook #11: ReelsDownloadHooks (STUB - full impl in Phase 1.5)\n");
    } @catch (NSException *e) {
        LOG("[dl/reels] init exc: %s\n", e.reason.UTF8String);
    }
}

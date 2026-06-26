// ExplorerHooks.xm - STUB
// UI Explorer (sendAction hook for debugging)
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

void initExplorerHooks(void) {
    @try {
        // Full implementation will be in Phase 1.5
        LOG("  hook: ExplorerHooks (STUB - full impl in Phase 1.5)\n");
    } @catch (NSException *e) {
        LOG("[dl/explorer] init exc: %s\n", e.reason.UTF8String);
    }
}

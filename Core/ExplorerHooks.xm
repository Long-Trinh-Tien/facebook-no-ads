// ExplorerHooks.xm
// UI Explorer - dumps view properties for debugging
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCommon.h"

void initExplorerHooks(void) {
    @try {
        // UIExplorer is for debugging - just log that it's initialized
        LOG("  hook: ExplorerHooks initialized (disabled by default)\n");
    } @catch (NSException *e) {
        LOG("[dl/explorer] init exc: %s\n", e.reason.UTF8String);
    }
}

// AdBlockHooks.xm
// Hooks for blocking ads in NewsFeed using Logos (Non-ARC)
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

%hook FBMemNewsFeedEdge

- (id)node {
    @try {
        id edgeObj = (id)self;
        SEL catSel = sel_registerName("category");
        if ([edgeObj respondsToSelector:catSel]) {
            id category = [edgeObj performSelector:catSel];
            if (category && [category respondsToSelector:@selector(isEqualToString:)]) {
                if (![category isEqualToString:@"ORGANIC"]) {
                    return nil; // Block all non-organic edges (SPONSORED, PROMOTION, SUGGESTED, etc.)
                }
            }
        }
    } @catch (NSException *e) {
        LOG("[adblock] Non-ARC exception: %s\n", e.reason.UTF8String);
    }
    return %orig;
}

%end

void initAdBlockHooks(void) {
    @try {
        if ([GlowSettingsManager shared].removeAds) {
            %init;
            LOG("  hook #0: FBMemNewsFeedEdge.node -> nil for non-ORGANIC (Logos Hook, Non-ARC)\n");
        }
    } @catch (NSException *e) {
        LOG("[dl/adblock] init exc: %s\n", e.reason.UTF8String);
    }
}

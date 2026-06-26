// GlowReelHandler.m
#import "GlowReelHandler.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowVideoHandler.h"
#import "GlowViewUtils.h"
#import "GlowCommon.h"
#import <objc/runtime.h>

@implementation GlowReelHandler

+ (instancetype)shared {
    static GlowReelHandler *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Reels Context Detection

- (BOOL)isInReelsFullScreen:(UIView *)sideBar {
    if (!sideBar) return NO;

    // Pass 1: Reject if immediate ancestors are comment/sheet
    UIView *cur = sideBar.superview;
    for (int depth = 0; cur && depth < 5; depth++) {
        const char *name = class_getName(object_getClass(cur));
        if (name) {
            if (strstr(name, "FBCommentStream") != NULL) return NO;
            if (strstr(name, "FBBottomSheetView") != NULL) return NO;
            if (strstr(name, "FBFeedAttachmentView") != NULL) return NO;
        }
        cur = cur.superview;
    }

    // Pass 2: Check full 30 ancestors for FBShorts
    cur = sideBar.superview;
    for (int depth = 0; cur && depth < 30; depth++) {
        const char *name = class_getName(object_getClass(cur));
        if (name && strstr(name, "FBShorts") != NULL) return YES;
        cur = cur.superview;
    }
    return NO;
}

- (UIView *)findReelsOverlayFrom:(UIView *)view {
    UIView *cur = view.superview;
    int depth = 0;
    while (cur && depth < 30) {
        Class cls = object_getClass(cur);
        const char *name = class_getName(cls);
        if (name && strstr(name, "FBShortsViewerOverlayComponentView") != NULL) {
            return cur;
        }
        cur = cur.superview;
        depth++;
    }
    return nil;
}

#pragma mark - Button Tap Handler

- (void)onReelButtonTap:(UIButton *)sender {
    if (![GlowSettingsManager shared].downloadReels) return;

    UIView *btnView = sender;
    UIView *thisSideBar = btnView.superview;
    NSValue *sbKey = [NSValue valueWithNonretainedObject:thisSideBar];
    GlowCacheManager *cache = [GlowCacheManager shared];
    NSDictionary *entry = [cache urlsForSidebar:thisSideBar];

    NSURL *hd = entry[@"HD"];
    NSURL *sd = entry[@"SD"];

    // M-3: Try active playing item
    if ((!hd && !sd)) {
        id active = cache.currentPlayingItem;
        if (active) {
            NSDictionary *itemEntry = [cache urlsForItem:active];
            hd = itemEntry[@"HD"];
            sd = itemEntry[@"SD"];
        }
    }

    if (!hd && !sd) {
        [GlowViewUtils showSafeToast:@"❌ Chưa có video để tải"];
        return;
    }

    [[GlowVideoHandler shared] presentQualityActionSheetHD:hd sd:sd sourceView:btnView];
}

#pragma mark - Add Download Button

- (void)addDownloadButtonToSidebar:(UIView *)sideBar {
    if (!sideBar || !sideBar.window) return;
    if (sideBar.hidden || sideBar.alpha < 0.01) return;
    if (sideBar.bounds.size.width < 40 || sideBar.bounds.size.height < 200) return;

    GlowCacheManager *cache = [GlowCacheManager shared];

    // Check FDS children count
    Class fdsCls = NSClassFromString(@"FDSTouchStateAnnouncingControl");
    if (!fdsCls) return;

    int fdsCount = 0;
    for (UIView *sub in sideBar.subviews) {
        if ([sub isKindOfClass:fdsCls]) fdsCount++;
    }
    if (fdsCount < 4) return;

    if (![self isInReelsFullScreen:sideBar]) return;

    UIView *overlay = [self findReelsOverlayFrom:sideBar];
    if (!overlay) return;

    NSValue *okey = [NSValue valueWithNonretainedObject:overlay];
    if ([cache.overlaysWithButton containsObject:okey]) return;

    // Position button above sidebar
    CGRect sbFrameInOverlay = [sideBar convertRect:sideBar.bounds toView:overlay];
    CGFloat btnW = 56;
    CGFloat btnH = 56;
    CGFloat btnX = sbFrameInOverlay.origin.x;
    CGFloat btnY = sbFrameInOverlay.origin.y - btnH - 8;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(btnX, btnY, btnW, btnH);
    btn.backgroundColor = [UIColor clearColor];
    [btn setTitle:@"⬇" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    btn.accessibilityIdentifier = @"GlowReelButton";
    btn.layer.zPosition = 9999;
    [btn addTarget:self action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:btn];
    [overlay bringSubviewToFront:btn];
    [cache.overlaysWithButton addObject:okey];

    LOG("[reels/main] ADDED button to overlay (FDS=%d)\n", fdsCount);
}

- (void)preWarmURLsForSidebar:(UIView *)sideBar {
    @try {
        UIResponder *r = sideBar.nextResponder;
        while (r) {
            if ([r isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)r;
                SEL itemSel = sel_registerName("currentVideoPlaybackItem");
                if ([vc respondsToSelector:itemSel]) {
                    id item = [vc performSelector:itemSel];
                    if (item) {
                        SEL hdSel = sel_registerName("HDPlaybackURL");
                        SEL sdSel = sel_registerName("SDPlaybackURL");
                        NSURL *hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
                        NSURL *sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
                        if (hd || sd) {
                            [[GlowCacheManager shared] setURLsForSidebar:sideBar hd:hd sd:sd];
                            LOG("[reels/main] Pre-warmed URLs for sidebar\n");
                        }
                    }
                }
                break;
            }
            r = [r nextResponder];
        }
    } @catch (NSException *e) {
        LOG("[reels/main] Pre-warm exc: %s\n", e.reason.UTF8String);
    }
}

@end

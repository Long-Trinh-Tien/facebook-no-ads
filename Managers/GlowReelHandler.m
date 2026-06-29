// GlowReelHandler.m
#import "GlowReelHandler.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowVideoHandler.h"
#import "GlowViewUtils.h"
#import "GlowCommon.h"
#import <objc/runtime.h>

static const NSInteger kReelsDownloadButtonTag = 8888;

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

static UIView *findSubViewOfClass(UIView *parent, Class cls) {
    if (!parent || !cls) return nil;
    if ([parent isKindOfClass:cls]) return parent;
    for (UIView *sub in parent.subviews) {
        UIView *found = findSubViewOfClass(sub, cls);
        if (found) return found;
    }
    return nil;
}

static UIView *findSiblingContainer(UIView *startView) {
    Class cls = objc_getClass("FBVideoPlaybackContainerView");
    if (!cls) cls = objc_getClass("FBVideoContainerView");
    if (!cls) cls = objc_getClass("FBFeedVideoContainerView");
    if (!cls) return nil;

    UIView *cur = startView;
    while (cur) {
        // If we hit a cell, do a local recursive search and stop there!
        if ([cur isKindOfClass:NSClassFromString(@"UICollectionViewCell")] || 
            [cur isKindOfClass:NSClassFromString(@"UITableViewCell")] ||
            [cur isKindOfClass:NSClassFromString(@"FBShortsViewerCell")]) {
            return findSubViewOfClass(cur, cls);
        }

        UIView *found = findSubViewOfClass(cur, cls);
        if (found) {
            return found;
        }
        if ([cur isKindOfClass:[UIWindow class]]) break;
        cur = cur.superview;
    }
    return nil;
}

static void collectViewsOfClass(UIView *parent, Class cls, NSMutableArray *results) {
    if (!parent) return;
    if ([parent isKindOfClass:cls]) {
        [results addObject:parent];
    }
    for (UIView *sub in parent.subviews) {
        collectViewsOfClass(sub, cls, results);
    }
}

static UIView *findVisibleVideoContainer(void) {
    Class cls = objc_getClass("FBVideoPlaybackContainerView");
    if (!cls) cls = objc_getClass("FBVideoContainerView");
    if (!cls) cls = objc_getClass("FBFeedVideoContainerView");
    if (!cls) return nil;

    // Collect all windows of the application
    NSMutableArray *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (id scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *window in ws.windows) {
                    if (window) [windows addObject:window];
                }
            }
        }
    }
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
    if (keyWin && ![windows containsObject:keyWin]) {
        [windows addObject:keyWin];
    }
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if (win && ![windows containsObject:win]) {
            [windows addObject:win];
        }
    }

    NSMutableArray *containers = [NSMutableArray array];
    for (UIWindow *window in windows) {
        collectViewsOfClass(window, cls, containers);
    }

    UIView *bestView = nil;
    CGFloat minDistance = CGFLOAT_MAX;
    
    // Use the bounds center of the key window as our target screen center
    UIWindow *mainWin = keyWin ? keyWin : ([windows count] > 0 ? windows[0] : nil);
    if (!mainWin) return nil;
    CGPoint screenCenter = CGPointMake(mainWin.bounds.size.width / 2.0, mainWin.bounds.size.height / 2.0);

    for (UIView *view in containers) {
        if (view.hidden || view.alpha < 0.01) continue;
        if (!view.window) continue;

        CGPoint viewCenter = CGPointMake(view.bounds.size.width / 2.0, view.bounds.size.height / 2.0);
        CGPoint centerInWindow = [view convertPoint:viewCenter toView:mainWin];

        CGFloat dx = centerInWindow.x - screenCenter.x;
        CGFloat dy = centerInWindow.y - screenCenter.y;
        CGFloat distance = sqrt(dx*dx + dy*dy);

        if (distance < minDistance) {
            minDistance = distance;
            bestView = view;
        }
    }
    return bestView;
}

static void dumpSubviewsRecursive(UIView *parent, int depth) {
    if (!parent || depth > 10) return;
    for (UIView *sub in parent.subviews) {
        LOG("[reels/diag]   %*s- %s (%p) frame=(%.1f,%.1f,%.1f,%.1f) hidden=%d alpha=%.2f\n", 
            depth * 2, "", class_getName(object_getClass(sub)), sub, sub.frame.origin.x, sub.frame.origin.y, sub.frame.size.width, sub.frame.size.height, sub.hidden, sub.alpha);
        
        if ([sub respondsToSelector:sel_registerName("currentVideoPlaybackItem")]) {
            LOG("[reels/diag]   %*s  -> RESPONDED to currentVideoPlaybackItem!\n", depth * 2, "");
        }
        
        // Also dump ivars for potential sub-player components
        const char *subName = class_getName(object_getClass(sub));
        if (strstr(subName, "Player") != NULL || strstr(subName, "Video") != NULL || strstr(subName, "Shorts") != NULL) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(object_getClass(sub), &count);
            for (unsigned int i = 0; i < count; i++) {
                Ivar iv = ivars[i];
                const char *ivName = ivar_getName(iv);
                const char *ivType = ivar_getTypeEncoding(iv);
                if (strstr(ivName, "controller") != NULL || strstr(ivName, "Controller") != NULL || strstr(ivName, "Player") != NULL) {
                    id val = nil;
                    if (ivType[0] == '@') val = safe_get_ivar(sub, iv);
                    LOG("[reels/diag]   %*s    Ivar: %s -> %s (%p)\n", depth * 2, "", ivName, val ? class_getName(object_getClass(val)) : "nil", val);
                }
            }
            if (ivars) free(ivars);
        }
        dumpSubviewsRecursive(sub, depth + 1);
    }
}

static void dumpViewDiagnostics(UIView *view) {
    if (!view) return;
    LOG("[reels/diag] ==========================================\n");
    LOG("[reels/diag] DIAGNOSTIC DUMP for %s (%p):\n", class_getName(object_getClass(view)), view);
    
    // 1. Print all ivars of the view
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(view), &ivarCount);
    LOG("[reels/diag] Ivars list (%d):\n", ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        Ivar ivar = ivars[i];
        const char *ivarName = ivar_getName(ivar);
        const char *ivarType = ivar_getTypeEncoding(ivar);
        ptrdiff_t offset = ivar_getOffset(ivar);
        id val = nil;
        if (ivarType[0] == '@') { // Object type
            val = safe_get_ivar(view, ivar);
        }
        LOG("[reels/diag]   - %s (type: %s, offset: %ld) -> value: %s (%p)\n",
            ivarName, ivarType, (long)offset, val ? class_getName(object_getClass(val)) : "nil", val);
    }
    if (ivars) free(ivars);

    // 2. Search subviews recursively
    LOG("[reels/diag] Subviews hierarchy search:\n");
    dumpSubviewsRecursive(view, 0);
    
    // 3. Search superviews (ancestors)
    LOG("[reels/diag] Superviews (ancestors) search:\n");
    UIView *curr = view.superview;
    int depth = 0;
    while (curr && depth < 15) {
        LOG("[reels/diag]   Depth %d: %s (%p)\n", depth, class_getName(object_getClass(curr)), curr);
        if ([curr respondsToSelector:sel_registerName("currentVideoPlaybackItem")]) {
            LOG("[reels/diag]     -> RESPONDED to currentVideoPlaybackItem!\n");
        }
        curr = curr.superview;
        depth++;
    }
    LOG("[reels/diag] ==========================================\n");
}

#pragma mark - Button Tap Handler

- (void)onReelButtonTap:(UIButton *)sender {
    LOG("[reels/button] ==========================================\n");
    LOG("[reels/button] Download button tapped!\n");
    if (![GlowSettingsManager shared].downloadReels) {
        LOG("[reels/button] ERROR: downloadReels is disabled in settings!\n");
        return;
    }

    UIView *btnView = sender;
    UIView *overlay = btnView.superview;
    LOG("[reels/button] Button parent: %s (%p)\n", overlay ? class_getName(object_getClass(overlay)) : "nil", overlay);
    
    // Resolve sidebar recursively from overlay's subviews
    UIView *sidebar = findSubViewOfClass(overlay, objc_getClass("FBShortsSideBarView"));
    LOG("[reels/button] Found sidebar in overlay: %p\n", sidebar);
    
    GlowCacheManager *cache = [GlowCacheManager shared];
    NSURL *hd = nil;
    NSURL *sd = nil;

    // 1. Direct Screen-Center Resolution (Absolute Precision): Find the playing video container on screen
    UIView *container = findVisibleVideoContainer();
    if (container) {
        LOG("[reels/button] 1. Screen-Center container found: %s (%p)\n", class_getName(object_getClass(container)), container);
        id controller = nil;
        if ([container respondsToSelector:@selector(delegate)]) {
            controller = [container performSelector:@selector(delegate)];
        }
        if (!controller) {
            Ivar ivar = class_getInstanceVariable(object_getClass(container), "_delegate");
            if (ivar) {
                controller = safe_get_ivar(container, ivar);
            }
        }
        if (!controller && [container respondsToSelector:@selector(controller)]) {
            controller = [container performSelector:@selector(controller)];
        }
        if (!controller && [container respondsToSelector:@selector(playbackController)]) {
            controller = [container performSelector:@selector(playbackController)];
        }
        if (!controller) {
            Ivar ivar = class_getInstanceVariable(object_getClass(container), "_videoPlaybackController");
            if (ivar) {
                controller = safe_get_ivar(container, ivar);
            }
        }
        if (!controller) {
            UIResponder *r = container;
            int depth = 0;
            while (r && depth < 20) {
                r = [r nextResponder];
                if ([r respondsToSelector:@selector(currentVideoPlaybackItem)]) {
                    controller = r;
                    break;
                }
                depth++;
            }
        }
        LOG("[reels/button]   Controller resolved: %s (%p)\n", controller ? class_getName(object_getClass(controller)) : "nil", controller);
        
        if (controller) {
            SEL itemSel = sel_registerName("currentVideoPlaybackItem");
            if ([controller respondsToSelector:itemSel]) {
                id item = [controller performSelector:itemSel];
                LOG("[reels/button]   PlaybackItem: %s (%p)\n", item ? class_getName(object_getClass(item)) : "nil", item);
                if (item) {
                    SEL hdSel = sel_registerName("HDPlaybackURL");
                    SEL sdSel = sel_registerName("SDPlaybackURL");
                    hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
                    sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
                    LOG("[reels/button]   URLs: HD=%s SD=%s\n", hd ? hd.absoluteString.UTF8String : "nil", sd ? sd.absoluteString.UTF8String : "nil");
                }
            } else {
                LOG("[reels/button]   Controller does NOT respond to currentVideoPlaybackItem!\n");
            }
        } else {
            // Trigger diagnostic dump if we failed to resolve controller from visible container
            dumpViewDiagnostics(container);
        }
    } else {
        LOG("[reels/button] 1. Screen-Center container NOT found!\n");
    }

    // 2. Fallback: Direct Sibling Resolution
    if (!hd && !sd) {
        LOG("[reels/button] 2. Trying fallback sibling resolution...\n");
        if (sidebar) {
            UIView *siblingContainer = findSiblingContainer(sidebar);
            if (siblingContainer) {
                LOG("[reels/button]   Sibling container found: %s (%p)\n", class_getName(object_getClass(siblingContainer)), siblingContainer);
                id controller = nil;
                if ([siblingContainer respondsToSelector:@selector(controller)]) {
                    controller = [siblingContainer performSelector:@selector(controller)];
                }
                if (!controller && [siblingContainer respondsToSelector:@selector(playbackController)]) {
                    controller = [siblingContainer performSelector:@selector(playbackController)];
                }
                LOG("[reels/button]   Controller: %s (%p)\n", controller ? class_getName(object_getClass(controller)) : "nil", controller);
                if (controller) {
                    SEL itemSel = sel_registerName("currentVideoPlaybackItem");
                    if ([controller respondsToSelector:itemSel]) {
                        id item = [controller performSelector:itemSel];
                        LOG("[reels/button]     PlaybackItem: %s (%p)\n", item ? class_getName(object_getClass(item)) : "nil", item);
                        if (item) {
                            SEL hdSel = sel_registerName("HDPlaybackURL");
                            SEL sdSel = sel_registerName("SDPlaybackURL");
                            hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
                            sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
                            LOG("[reels/button]     URLs: HD=%s SD=%s\n", hd ? hd.absoluteString.UTF8String : "nil", sd ? sd.absoluteString.UTF8String : "nil");
                        }
                    }
                }
            } else {
                LOG("[reels/button]   Sibling container NOT found!\n");
            }
        }
    }

    // 3. Fallback: Direct Responder Chain Walk
    if (!hd && !sd) {
        LOG("[reels/button] 3. Trying fallback responder chain walk...\n");
        if (sidebar) {
            UIResponder *r = sidebar;
            int depth = 0;
            while (r && depth < 30) {
                SEL itemSel = sel_registerName("currentVideoPlaybackItem");
                if ([r respondsToSelector:itemSel]) {
                    id item = [r performSelector:itemSel];
                    LOG("[reels/button]   Depth %d: %s (%p) responds to currentVideoPlaybackItem -> item: %p\n", depth, class_getName(object_getClass(r)), r, item);
                    if (item) {
                        SEL hdSel = sel_registerName("HDPlaybackURL");
                        SEL sdSel = sel_registerName("SDPlaybackURL");
                        hd = [item respondsToSelector:hdSel] ? [item performSelector:hdSel] : nil;
                        sd = [item respondsToSelector:sdSel] ? [item performSelector:sdSel] : nil;
                        LOG("[reels/button]     URLs: HD=%s SD=%s\n", hd ? hd.absoluteString.UTF8String : "nil", sd ? sd.absoluteString.UTF8String : "nil");
                        if (hd || sd) break;
                    }
                }
                r = [r nextResponder];
                depth++;
            }
        }
    }

    // 4. Fallback: Try active playing item in cache
    if (!hd && !sd) {
        LOG("[reels/button] 4. Trying fallback active playing item cache...\n");
        id active = cache.currentPlayingItem;
        LOG("[reels/button]   Active playing item in cache: %p\n", active);
        if (active) {
            NSDictionary *itemEntry = [cache urlsForItem:active];
            hd = itemEntry[@"HD"];
            sd = itemEntry[@"SD"];
            LOG("[reels/button]   Cached URLs: HD=%s SD=%s\n", hd ? hd.absoluteString.UTF8String : "nil", sd ? sd.absoluteString.UTF8String : "nil");
        }
    }

    // 5. Fallback: Try pre-warmed sidebar URLs
    if (!hd && !sd) {
        LOG("[reels/button] 5. Trying fallback pre-warmed sidebar URLs...\n");
        if (sidebar) {
            NSDictionary *entry = [cache urlsForSidebar:sidebar];
            hd = entry[@"HD"];
            sd = entry[@"SD"];
            LOG("[reels/button]   Sidebar cached URLs: HD=%s SD=%s\n", hd ? hd.absoluteString.UTF8String : "nil", sd ? sd.absoluteString.UTF8String : "nil");
        }
    }

    // 6. Ultimate Fallback: Try global captured cached URLs
    if (!hd && !sd) {
        LOG("[reels/button] 6. Trying ultimate global captured cache...\n");
        hd = cache.cachedHDURL;
        sd = cache.cachedSDURL;
        LOG("[reels/button]   Global cache URLs: HD=%s SD=%s\n", hd ? hd.absoluteString.UTF8String : "nil", sd ? sd.absoluteString.UTF8String : "nil");
    }

    if (!hd && !sd) {
        LOG("[reels/button] FAILED: No video URLs resolved!\n");
        [GlowViewUtils showSafeToast:@"❌ Chưa có video để tải"];
        return;
    }

    LOG("[reels/button] SUCCESS: Presenting ActionSheet...\n");
    [[GlowVideoHandler shared] presentQualityActionSheetHD:hd sd:sd sourceView:btnView];
}

#pragma mark - Add Download Button

- (void)addDownloadButtonToSidebar:(UIView *)sideBar {
    if (!sideBar || !sideBar.window) return;
    if (sideBar.hidden || sideBar.alpha < 0.01) return;
    if (sideBar.bounds.size.width < 40 || sideBar.bounds.size.height < 200) return;

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

    // Calculate correct position above sidebar in overlay coordinate space
    CGRect sbFrameInOverlay = [sideBar convertRect:sideBar.bounds toView:overlay];
    // Return early if the sidebar has not been positioned yet (x or y is 0/invalid)
    if (sbFrameInOverlay.origin.x < 10 || sbFrameInOverlay.origin.y < 10) return;

    CGFloat btnW = 56;
    CGFloat btnH = 56;
    CGFloat btnX = sbFrameInOverlay.origin.x + (sideBar.bounds.size.width - btnW) / 2;
    CGFloat btnY = sbFrameInOverlay.origin.y - btnH - 12;

    UIButton *btn = (UIButton *)[overlay viewWithTag:kReelsDownloadButtonTag];
    if (btn) {
        // Dynamic repositioning: update button's frame to follow the sidebar shifts
        btn.frame = CGRectMake(btnX, btnY, btnW, btnH);
        [overlay bringSubviewToFront:btn];
        return;
    }

    btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = kReelsDownloadButtonTag;
    btn.frame = CGRectMake(btnX, btnY, btnW, btnH);
    
    // Aesthetic Styling
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    btn.layer.cornerRadius = btnW / 2;
    btn.clipsToBounds = YES;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, btnW, btnH)];
    label.text = @"⬇";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    label.textAlignment = NSTextAlignmentCenter;
    [btn addSubview:label];
    
    btn.accessibilityIdentifier = @"GlowReelButton";
    btn.layer.zPosition = 9999;
    [btn addTarget:self action:@selector(onReelButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    
    [overlay addSubview:btn];
    [overlay bringSubviewToFront:btn];

    LOG("[reels/main] ADDED button to overlay: x=%.1f y=%.1f (FDS=%d)\n", btnX, btnY, fdsCount);
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
